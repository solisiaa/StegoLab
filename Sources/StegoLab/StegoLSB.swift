import AppKit
import CoreGraphics

/// LSB-стеганография с заменой 1 младшего бита.
/// Каждый бит полезной нагрузки записывается в младший бит байтов R, G, B пикселей.
/// Формат v2: [MAGIC "STG2" 4 байта] + [режим 1 байт: 0=текст, 1=файл]
///   текст: [длина текста 32 бита] + [байты UTF-8]
///   файл:  [длина имени 16 бит] + [имя UTF-8] + [длина файла 32 бита] + [байты файла любого типа]
/// Старый формат v1 (только текст без MAGIC) тоже читается — для совместимости.
enum StegoLSB {

    enum StegoError: LocalizedError {
        case cannotGetPixels
        case messageTooLarge(capacityBytes: Int, neededBytes: Int)
        case invalidImage
        case noMarkerOrCorrupted
        case notUTF8
        case isFileNotText

        var errorDescription: String? {
            switch self {
            case .cannotGetPixels:
                return "Не удалось получить пиксели изображения"
            case .messageTooLarge(let cap, let need):
                return "Не помещается: вместимость \(cap) байт, нужно \(need) байт. Возьмите картинку больше или файл меньше."
            case .invalidImage:
                return "Некорректное изображение"
            case .noMarkerOrCorrupted:
                return "В изображении нет зашифрованных данных (неверная длина или поврежденные данные)"
            case .notUTF8:
                return "Извлеченные байты — не валидный UTF-8 текст"
            case .isFileNotText:
                return "В картинке спрятан файл, а не текст — смотри блок файла ниже"
            }
        }
    }

    enum Payload {
        case text(String)
        case file(name: String, data: Data)
    }

    private static let magic: [UInt8] = [0x53, 0x54, 0x47, 0x32] // "STG2"

    // MARK: - Public API: текст

    /// Встроить текстовое сообщение (режим 0).
    static func embed(message: String, into image: CGImage) throws -> CGImage {
        let payload = buildTextPayload(text: message)
        return try embedPayloadBytes(payload, into: image)
    }

    /// Извлечь текст (работает и со старыми картинками v1, и с новыми v2-текст).
    static func extract(from image: CGImage) throws -> String {
        let payload = try extractPayload(from: image)
        switch payload {
        case .text(let s): return s
        case .file: throw StegoError.isFileNotText
        }
    }

    // MARK: - Public API: файлы (любое расширение)

    /// Встроить файл любого типа. Имя файла сохраняется, чтобы при расшифровке предложить то же имя.
    static func embedFile(name: String, data: Data, into image: CGImage) throws -> CGImage {
        let payload = buildFilePayload(fileName: name, fileData: data)
        return try embedPayloadBytes(payload, into: image)
    }

    /// Извлечь полезную нагрузку: текст или файл.
    static func extractPayload(from image: CGImage) throws -> Payload {
        let lsb = try lsbArray(from: image)
        // Сначала пробуем новый формат v2 по MAGIC
        if startsWithMagic(lsb) {
            return try parseV2(lsb: lsb)
        }
        // Иначе — старый формат v1: [длина 32 бита] + [UTF-8]
        return try parseV1(lsb: lsb)
    }

    /// Вместимость под полезные данные (с учетом заголовка v2).
    static func capacityBytes(of image: CGImage) -> Int {
        // заголовок v2-текст: 4 (magic) + 1 (режим) + 4 (длина) = 9 байт
        max((image.width * image.height * 3 - 9 * 8) / 8, 0)
    }

    // MARK: - Построение полезной нагрузки (байты → потом в биты)

    private static func buildTextPayload(text: String) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(0) // режим текст
        let t = Data(text.utf8)
        out.append(contentsOf: u32Bytes(UInt32(t.count)))
        out.append(t)
        return out
    }

    private static func buildFilePayload(fileName: String, fileData: Data) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(1) // режим файл
        let nameBytes = Data(fileName.utf8)
        let nameLen = UInt16(min(nameBytes.count, 65535))
        out.append(UInt8((nameLen >> 8) & 0xFF))
        out.append(UInt8(nameLen & 0xFF))
        out.append(contentsOf: nameBytes.prefix(Int(nameLen)))
        out.append(contentsOf: u32Bytes(UInt32(fileData.count)))
        out.append(fileData)
        return out
    }

    private static func u32Bytes(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    // MARK: - Низкоуровневое встраивание байтов в LSB

    private static func embedPayloadBytes(_ payload: Data, into image: CGImage) throws -> CGImage {
        guard let rgba = Self.rgbaBytes(from: image) else {
            throw StegoError.cannotGetPixels
        }
        var pixels = rgba.bytes
        let capacityBits = rgba.width * rgba.height * 3
        let needBits = payload.count * 8
        guard needBits <= capacityBits else {
            let capBytes = max(capacityBits / 8 - 9, 0)
            throw StegoError.messageTooLarge(capacityBytes: capBytes, neededBytes: payload.count)
        }
        // Байты → биты, старшим битом вперед
        var bitIndex = 0
        let totalBits = needBits
        for i in 0..<pixels.count {
            if i % 4 == 3 { continue } // alpha — не трогаем
            if bitIndex >= totalBits { break }
            let byteIdx = bitIndex / 8
            let bitInByte = 7 - (bitIndex % 8)
            let bit = (payload[byteIdx] >> bitInByte) & 1
            pixels[i] = (pixels[i] & 0xFE) | bit
            bitIndex += 1
        }
        guard bitIndex == totalBits else {
            throw StegoError.messageTooLarge(capacityBytes: capacityBits / 8, neededBytes: payload.count)
        }
        return try makeCGImage(from: pixels, width: rgba.width, height: rgba.height)
    }

    // MARK: - Чтение LSB и разбор

    private static func lsbArray(from image: CGImage) throws -> [UInt8] {
        guard let rgba = Self.rgbaBytes(from: image) else {
            throw StegoError.cannotGetPixels
        }
        var lsb: [UInt8] = []
        lsb.reserveCapacity(rgba.width * rgba.height * 3)
        for i in 0..<rgba.bytes.count {
            if i % 4 == 3 { continue }
            lsb.append(rgba.bytes[i] & 1)
        }
        return lsb
    }

    private static func startsWithMagic(_ lsb: [UInt8]) -> Bool {
        guard lsb.count >= 4 * 8 else { return false }
        let bytes = bitsToBytes(lsb: lsb, offset: 0, count: 4)
        return bytes == magic
    }

    private static func parseV2(lsb: [UInt8]) throws -> Payload {
        // [magic 4][mode 1][...]
        guard lsb.count >= 5 * 8 else { throw StegoError.noMarkerOrCorrupted }
        let mode = bitsToBytes(lsb: lsb, offset: 4 * 8, count: 1)[0]
        if mode == 0 {
            // текст: [len 4][text]
            guard lsb.count >= 9 * 8 else { throw StegoError.noMarkerOrCorrupted }
            let lenBytes = bitsToBytes(lsb: lsb, offset: 5 * 8, count: 4)
            let len = (UInt32(lenBytes[0]) << 24) | (UInt32(lenBytes[1]) << 16) | (UInt32(lenBytes[2]) << 8) | UInt32(lenBytes[3])
            let maxBytes = (lsb.count - 9 * 8) / 8
            guard len <= maxBytes else { throw StegoError.noMarkerOrCorrupted }
            let textBytes = bitsToBytes(lsb: lsb, offset: 9 * 8, count: Int(len))
            guard let s = String(data: Data(textBytes), encoding: .utf8) else {
                throw StegoError.notUTF8
            }
            return .text(s)
        } else if mode == 1 {
            // файл: [nameLen 2][name][fileLen 4][file]
            guard lsb.count >= 7 * 8 else { throw StegoError.noMarkerOrCorrupted }
            let nlBytes = bitsToBytes(lsb: lsb, offset: 5 * 8, count: 2)
            let nameLen = Int(nlBytes[0]) * 256 + Int(nlBytes[1])
            let headerBytes = 7 + nameLen + 4
            guard lsb.count >= headerBytes * 8 else { throw StegoError.noMarkerOrCorrupted }
            let nameBytes = bitsToBytes(lsb: lsb, offset: 7 * 8, count: nameLen)
            let fileName = String(data: Data(nameBytes), encoding: .utf8) ?? "file.bin"
            let lenBytes = bitsToBytes(lsb: lsb, offset: (7 + nameLen) * 8, count: 4)
            let fileLen = (UInt32(lenBytes[0]) << 24) | (UInt32(lenBytes[1]) << 16) | (UInt32(lenBytes[2]) << 8) | UInt32(lenBytes[3])
            let maxBytes = (lsb.count - headerBytes * 8) / 8
            guard fileLen <= maxBytes else { throw StegoError.noMarkerOrCorrupted }
            let fileBytes = bitsToBytes(lsb: lsb, offset: headerBytes * 8, count: Int(fileLen))
            return .file(name: fileName, data: Data(fileBytes))
        } else {
            throw StegoError.noMarkerOrCorrupted
        }
    }

    private static func parseV1(lsb: [UInt8]) throws -> Payload {
        // Старый формат: [длина 32 бита] + [UTF-8] — считаем текстом
        guard lsb.count >= 32 else { throw StegoError.noMarkerOrCorrupted }
        var length: UInt32 = 0
        for i in 0..<32 {
            length = (length << 1) | UInt32(lsb[i])
        }
        let maxBytes = (lsb.count - 32) / 8
        guard length <= maxBytes else { throw StegoError.noMarkerOrCorrupted }
        let dataBytes = bitsToBytes(lsb: lsb, offset: 32, count: Int(length))
        guard let s = String(data: Data(dataBytes), encoding: .utf8) else {
            throw StegoError.notUTF8
        }
        return .text(s)
    }

    /// Взять count байт из массива бит начиная с offset (в битах).
    private static func bitsToBytes(lsb: [UInt8], offset: Int, count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        var idx = offset
        for _ in 0..<count {
            var b: UInt8 = 0
            for _ in 0..<8 {
                b = (b << 1) | lsb[idx]
                idx += 1
            }
            out.append(b)
        }
        return out
    }

    // MARK: - Pixel helpers (RGBA8, alpha последний байт)

    private struct RGBA {
        var bytes: [UInt8]
        var width: Int
        var height: Int
    }

    private static func rgbaBytes(from image: CGImage) -> RGBA? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBA(bytes: bytes, width: width, height: height)
    }

    private static func makeCGImage(from pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        var pixels = pixels
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let out = ctx.makeImage() else {
            throw StegoError.invalidImage
        }
        guard let copy = out.copy() else { throw StegoError.invalidImage }
        return copy
    }
}
