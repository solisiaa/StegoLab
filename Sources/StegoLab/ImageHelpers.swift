import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageHelpers {
    /// Диалог открытия картинки -> (NSImage для показа, CGImage для алгоритма, URL)
    /// NSImage — показать, CGImage — посчитать; нормализация через TIFF держит PNG/JPEG/BMP
    @MainActor
    static func openImage() -> (NSImage, CGImage, URL)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .bmp, .tiff]
        panel.message = "Выберите изображение (лучше PNG/BMP — JPEG с потерями разрушает младшие биты)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImageForStego() else { return nil }
        return (nsImage, cg, url)
    }

    /// Диалог сохранения stego-картинки в PNG
    /// только PNG lossless — JPEG пересчитает цвета и сотрет младшие биты
    @MainActor
    static func savePNG(cgImage: CGImage) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "stego.png"
        panel.message = "Сохраните в PNG (JPEG разрушит скрытое сообщение!)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// Диалог выбора любого файла для шифрования -> (имя, байты)
    /// Работает с любым расширением: прячем байты как есть, имя сохраняем отдельно
    @MainActor
    static func openAnyFile() -> (name: String, data: Data)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Выберите любой файл для шифрования в картинке"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (url.lastPathComponent, data)
    }

    /// Диалог сохранения извлеченного файла на диск с исходным именем
    @MainActor
    static func saveFile(data: Data, suggestedName: String) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.message = "Сохраните извлеченный файл"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

extension NSImage {
    /// Нормализация к CGImage (через TIFF-представление — самый надежный путь для PNG/JPEG/BMP).
    func cgImageForStego() -> CGImage? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return nil }
        return cg
    }
}
