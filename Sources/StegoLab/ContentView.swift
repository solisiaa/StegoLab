import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        TabView {
            EncryptView()
                .tabItem { Label("Шифрование", systemImage: "lock.fill") }
            DecryptView()
                .tabItem { Label("Дешифрование", systemImage: "lock.open.fill") }
        }
        .padding(12)
    }
}

// MARK: - Модуль 1: Шифрование

// МОДУЛЬ 1 — Шифрование: 3 кнопки по заданию + блок текста + блок файла
struct EncryptView: View {
    // NSImage — для показа на экране, CGImage — для математики алгоритма
    @State private var originalNS: NSImage?
    @State private var originalCG: CGImage?
    @State private var mode: Int = 0 // 0 = текст, 1 = файл
    @State private var message: String = "" // сюда печатаешь свой текст, он и шифруется
    @State private var fileName: String = ""
    @State private var fileData: Data? = nil
    @State private var stegoNS: NSImage?
    @State private var stegoCG: CGImage?
    @State private var status: String = "Загрузите фотографию, выберите текст или файл и нажмите «Зашифровать»."

    var capacityText: String {
        guard let cg = originalCG else { return "—" }
        return "\(StegoLSB.capacityBytes(of: cg)) байт"
    }

    var payloadBytes: Int {
        if mode == 0 { return message.utf8.count }
        return fileData?.count ?? 0
    }

    var canEncrypt: Bool {
        guard originalCG != nil else { return false }
        if mode == 0 { return !message.isEmpty }
        return fileData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Модуль 1 — Шифрование (LSB: замена 1 младшего бита)")
                .font(.headline)

            HStack(spacing: 10) {
                // КНОПКА 1: открыть исходник (показ + пиксели для embed)
                Button("Загрузить исходную фотографию") {
                    if let (ns, cg, _) = ImageHelpers.openImage() {
                        originalNS = ns
                        originalCG = cg
                        stegoNS = nil
                        stegoCG = nil
                        status = "Фото загружено: \(cg.width)×\(cg.height). Вместимость: \(StegoLSB.capacityBytes(of: cg)) байт."
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                // КНОПКА 2: вызвать алгоритм embed (текст или файл в зависимости от переключателя)
                Button("Зашифровать") {
                    doEncrypt()
                }
                .disabled(!canEncrypt)
                .keyboardShortcut(.return, modifiers: .command)

                // КНОПКА 3: сохранить ТОЛЬКО в PNG (JPEG стер бы младшие биты!)
                Button("Сохранить зашифрованную картинку на диск") {
                    guard let cg = stegoCG else { return }
                    if ImageHelpers.savePNG(cgImage: cg) {
                        status = "✅ Сохранено в PNG. Передайте этот файл для расшифровки."
                    } else {
                        status = "Сохранение отменено."
                    }
                }
                .disabled(stegoCG == nil)
            }

            Text("Вместимость изображения: \(capacityText). Нагрузка: \(payloadBytes) байт.")
                .font(.callout)
                .foregroundColor(.secondary)

            // Переключатель: что прячем — текст или файл любого расширения
            Picker("Что шифруем:", selection: $mode) {
                Text("Текст").tag(0)
                Text("Файл").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            if mode == 0 {
                Text("Текстовое сообщение (пишите свой текст сюда):")
                    .font(.subheadline)
                // Поле текста: что напечатаешь — то и встроится в картинку
                TextField("Введите сюда свой секретный текст...", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .frame(minHeight: 90)
                    .focusable(true)
                HStack {
                    Spacer()
                    Button("Очистить поле") { message = "" }
                        .disabled(message.isEmpty)
                }
            } else {
                Text("Файл любого типа (документ, картинка, архив...):")
                    .font(.subheadline)
                // Блок файла: выбираешь любой файл, прячем его байты + имя
                HStack {
                    Button("Выбрать файл...") {
                        if let (name, data) = ImageHelpers.openAnyFile() {
                            fileName = name
                            fileData = data
                            stegoNS = nil
                            stegoCG = nil
                            status = "Файл выбран: \(name), \(data.count) байт."
                        }
                    }
                    if let data = fileData {
                        Text("\(fileName) (\(data.count) байт)")
                            .font(.callout)
                        Spacer()
                        Button("Убрать") {
                            fileName = ""
                            fileData = nil
                        }
                    } else {
                        Text("файл не выбран").foregroundColor(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack {
                    Text("Исходная").font(.subheadline)
                    imagePreview(originalNS, placeholder: "нет фото")
                }
                VStack {
                    Text("Зашифрованная").font(.subheadline)
                    imagePreview(stegoNS, placeholder: "нажмите «Зашифровать»")
                }
            }

            Text(status)
                .font(.callout)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(4)
    }

    // Связка UI и алгоритма: текст уходит в embed(message:), файл — в embedFile
    private func doEncrypt() {
        guard let cg = originalCG else { return }
        do {
            let stego: CGImage
            if mode == 0 {
                stego = try StegoLSB.embed(message: message, into: cg)
                status = "✅ Текст зашифрован! Встроено \(message.utf8.count) байт. Сохраните картинку кнопкой 3."
            } else {
                guard let data = fileData else { return }
                stego = try StegoLSB.embedFile(name: fileName, data: data, into: cg)
                status = "✅ Файл зашифрован! Встроено \(data.count) байт (\(fileName)). Сохраните картинку кнопкой 3."
            }
            stegoCG = stego
            stegoNS = NSImage(cgImage: stego, size: NSSize(width: stego.width, height: stego.height))
        } catch {
            status = "❌ Ошибка: \(error.localizedDescription)"
        }
    }

    private func imagePreview(_ img: NSImage?, placeholder: String) -> some View {
        Group {
            if let img {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 380, maxHeight: 220)
                    .border(Color.gray.opacity(0.3))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(dash: [6]))
                    .frame(width: 380, height: 160)
                    .overlay(Text(placeholder).foregroundColor(.secondary))
            }
        }
    }
}

// MARK: - Модуль 2: Дешифрование

// МОДУЛЬ 2 — Дешифрование: 2 кнопки открытия + расшифровать + поле текста + блок файла
// оригинал нужен по заданию (для сравнения), читаем только из stego!
struct DecryptView: View {
    @State private var originalNS: NSImage?
    @State private var originalCG: CGImage?
    @State private var stegoNS: NSImage?
    @State private var stegoCG: CGImage?
    @State private var result: String = ""
    @State private var outFileName: String = ""
    @State private var outFileData: Data? = nil
    @State private var status: String = "Откройте оба изображения и нажмите «Расшифровать»."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Модуль 2 — Дешифрование")
                .font(.headline)

            HStack(spacing: 10) {
                // КНОПКА 1: оригинал — только для показа рядом, в математике не участвует
                Button("Открыть исходное изображение") {
                    if let (ns, cg, _) = ImageHelpers.openImage() {
                        originalNS = ns
                        originalCG = cg
                        status = "Исходное загружено: \(cg.width)×\(cg.height). Теперь откройте зашифрованное."
                    }
                }
                // КНОПКА 2: stego-картинка — именно из нее извлекаем биты
                // файл показывается сразу: как только открыли картинку, тут же расшифровываем
                Button("Открыть изображение с зашифрованным сообщением") {
                    if let (ns, cg, _) = ImageHelpers.openImage() {
                        stegoNS = ns
                        stegoCG = cg
                        // авторасшифровка — не надо жать кнопку 3, результат появится сам
                        doDecrypt()
                    }
                }
                // КНОПКА 3: вызвать алгоритм extractPayload, дальше смотрим режим текст/файл
                // оставлена по заданию, но обычно уже не нужна — все показалось само
                Button("Расшифровать") {
                    doDecrypt()
                }
                .disabled(stegoCG == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }

            Text("Оригинал нужен для визуального сравнения. Извлечение идет из младших бит зашифрованной картинки.")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack {
                    Text("Исходная").font(.subheadline)
                    imagePreview(originalNS, placeholder: "кнопка 1")
                }
                VStack {
                    Text("С данными").font(.subheadline)
                    imagePreview(stegoNS, placeholder: "кнопка 2")
                }
            }

            HStack {
                Text("Расшифрованное сообщение:")
                    .font(.subheadline)
                Spacer()
                Button("Копировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
                .disabled(result.isEmpty)
            }
            // Поле вывода: сюда ляжет расшифрованный текст (если был спрятан текст)
            TextField("Здесь появится расшифрованный текст...", text: $result, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .frame(minHeight: 70)
                .textSelection(.enabled)

            // Блок файла: появляется сразу после открытия картинки, ждать кнопку не надо
            // если внутри картинка — показываем миниатюру, если текст — кусок содержимого
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Извлеченный файл:")
                        .font(.subheadline)
                    if let data = outFileData {
                        Text("\(outFileName) (\(data.count) байт)")
                            .font(.callout)
                        Spacer()
                        Button("Открыть") {
                            openExtractedFile()
                        }
                        Button("Сохранить файл на диск...") {
                            if ImageHelpers.saveFile(data: data, suggestedName: outFileName) {
                                status = "✅ Файл сохранен: \(outFileName)"
                            }
                        }
                    } else {
                        Text("откройте картинку — файл появится сам").foregroundColor(.secondary)
                    }
                }
                // предпросмотр содержимого файла прямо в окне
                if let data = outFileData {
                    filePreview(name: outFileName, data: data)
                }
            }

            Text(status)
                .font(.callout)
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(4)
    }

    // Извлечение идет ТОЛЬКО из stego; дальше ветвление: текст — в поле, файл — в блок файла
    private func doDecrypt() {
        guard let stego = stegoCG else { return }
        if let orig = originalCG, (orig.width != stego.width || orig.height != stego.height) {
            status = "⚠️ Размеры отличаются (\(orig.width)×\(orig.height) vs \(stego.width)×\(stego.height)). Пробую извлечь..."
        }
        do {
            switch try StegoLSB.extractPayload(from: stego) {
            case .text(let s):
                result = s
                outFileData = nil
                outFileName = ""
                status = "✅ Расшифрован текст! Извлечено \(s.utf8.count) байт."
            case .file(let name, let data):
                result = ""
                outFileName = name
                outFileData = data
                status = "✅ Расшифрован файл \(name) (\(data.count) байт). Сохраните его кнопкой выше."
            }
        } catch {
            result = ""
            outFileData = nil
            status = "❌ Ошибка: \(error.localizedDescription)"
        }
    }

    private func imagePreview(_ img: NSImage?, placeholder: String) -> some View {
        Group {
            if let img {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 380, maxHeight: 200)
                    .border(Color.gray.opacity(0.3))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(dash: [6]))
                    .frame(width: 380, height: 150)
                    .overlay(Text(placeholder).foregroundColor(.secondary))
            }
        }
    }

    // Миниатюра извлеченного файла: картинку показываем картинкой, текст — текстом
    @ViewBuilder
    private func filePreview(name: String, data: Data) -> some View {
        let ext = (name as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "bmp", "tiff", "gif", "heic"].contains(ext),
           let img = NSImage(data: data) {
            HStack {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 140)
                    .border(Color.gray.opacity(0.3))
                Text("предпросмотр картинки из файла").foregroundColor(.secondary).font(.callout)
                Spacer()
            }
        } else if ["txt", "md", "csv", "json", "swift", "c", "h", "py", "log"].contains(ext),
                  let s = String(data: data, encoding: .utf8) {
            Text(s.prefix(500))
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        } else {
            Text("нажми «Открыть», чтобы посмотреть файл во внешней программе")
                .foregroundColor(.secondary).font(.callout)
        }
    }

    // Открыть извлеченный файл во внешней программе через временный файл
    private func openExtractedFile() {
        guard let data = outFileData else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(outFileName)
        do {
            try data.write(to: tmp)
            NSWorkspace.shared.open(tmp)
        } catch {
            status = "❌ Не смог открыть файл: \(error.localizedDescription)"
        }
    }
}
