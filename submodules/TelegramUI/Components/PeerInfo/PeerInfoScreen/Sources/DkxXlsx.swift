import Foundation
import ZipArchive

// Минимальная книга .xlsx своими силами, из сторонних только ZIP. Первая строка листа жирная

enum DkxXlsxCell {
    case text(String)
    case number(Double)
}

struct DkxXlsxSheet {
    let name: String
    let rows: [[DkxXlsxCell]]
}

private func dkxXlsxColumn(_ index: Int) -> String {
    var result = ""
    var value = index + 1
    while value > 0 {
        let remainder = (value - 1) % 26
        result = String(UnicodeScalar(UInt8(65 + remainder))) + result
        value = (value - 1) / 26
    }
    return result
}

// Управляющие символы XML не пропускает, даже экранированными
private func dkxXlsxEscape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    for scalar in text.unicodeScalars {
        switch scalar {
        case "&":
            result += "&amp;"
        case "<":
            result += "&lt;"
        case ">":
            result += "&gt;"
        case "\"":
            result += "&quot;"
        case "'":
            result += "&apos;"
        default:
            if scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D {
                continue
            }
            if scalar.value == 0xFFFE || scalar.value == 0xFFFF {
                continue
            }
            result.unicodeScalars.append(scalar)
        }
    }
    return result
}

private func dkxXlsxNumber(_ value: Double) -> String {
    if value.isNaN || value.isInfinite {
        return "0"
    }
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int64(value))
    }
    return String(value)
}

// Имя листа до 31 символа и без []:*?/\, повторы получают номер
private func dkxXlsxSheetNames(_ names: [String]) -> [String] {
    var used = Set<String>()
    var result: [String] = []
    for (index, name) in names.enumerated() {
        var clean = String(name.filter { !"[]:*?/\\".contains($0) }.prefix(31))
        if clean.isEmpty {
            clean = "Sheet\(index + 1)"
        }
        var candidate = clean
        var counter = 2
        while used.contains(candidate.lowercased()) {
            let suffix = " \(counter)"
            candidate = String(clean.prefix(31 - suffix.count)) + suffix
            counter += 1
        }
        used.insert(candidate.lowercased())
        result.append(candidate)
    }
    return result
}

private func dkxXlsxSheetXml(_ sheet: DkxXlsxSheet) -> String {
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
    for (rowIndex, row) in sheet.rows.enumerated() {
        let rowNumber = rowIndex + 1
        xml += "<row r=\"\(rowNumber)\">"
        for (columnIndex, cell) in row.enumerated() {
            let reference = dkxXlsxColumn(columnIndex) + "\(rowNumber)"
            let style = rowIndex == 0 ? " s=\"1\"" : ""
            switch cell {
            case let .text(value):
                xml += "<c r=\"\(reference)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(dkxXlsxEscape(value))</t></is></c>"
            case let .number(value):
                xml += "<c r=\"\(reference)\"\(style)><v>\(dkxXlsxNumber(value))</v></c>"
            }
        }
        xml += "</row>"
    }
    xml += "</sheetData></worksheet>"
    return xml
}

func dkxWriteXlsx(sheets: [DkxXlsxSheet], to path: String) -> Bool {
    let fileManager = FileManager.default
    let directory = NSTemporaryDirectory() + "dkx-xlsx-\(UInt64.random(in: 0 ... UInt64.max))"
    defer {
        let _ = try? fileManager.removeItem(atPath: directory)
    }
    let names = dkxXlsxSheetNames(sheets.map { $0.name })
    let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    var contentTypes = header + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
    contentTypes += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
    contentTypes += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
    contentTypes += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
    contentTypes += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
    for index in 0 ..< sheets.count {
        contentTypes += "<Override PartName=\"/xl/worksheets/sheet\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
    }
    contentTypes += "</Types>"

    let rootRels = header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"

    var workbook = header + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
    var workbookRels = header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
    for index in 0 ..< sheets.count {
        workbook += "<sheet name=\"\(dkxXlsxEscape(names[index]))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        workbookRels += "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
    }
    workbook += "</sheets></workbook>"
    workbookRels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"

    let styles = header + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"

    var files: [(String, String)] = [
        ("[Content_Types].xml", contentTypes),
        ("_rels/.rels", rootRels),
        ("xl/workbook.xml", workbook),
        ("xl/_rels/workbook.xml.rels", workbookRels),
        ("xl/styles.xml", styles)
    ]
    for (index, sheet) in sheets.enumerated() {
        files.append(("xl/worksheets/sheet\(index + 1).xml", dkxXlsxSheetXml(sheet)))
    }

    do {
        for (relativePath, content) in files {
            let fullPath = directory + "/" + relativePath
            try fileManager.createDirectory(atPath: (fullPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: URL(fileURLWithPath: fullPath))
        }
    } catch {
        return false
    }
    let _ = try? fileManager.removeItem(atPath: path)
    return SSZipArchive.createZipFile(atPath: path, withContentsOfDirectory: directory)
}
