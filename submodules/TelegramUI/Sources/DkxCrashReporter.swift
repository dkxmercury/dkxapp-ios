import Foundation
import MetricKit
import TelegramCore

// MARK: DKX. Отчёты о падениях и зависаниях через системный MetricKit.
//
// Своего сборщика у форка нет: AppCenter в апстриме подключается только для
// официального идентификатора приложения. iOS сама собирает отчёт о падении
// и отдаёт его приложению при следующем запуске, иногда с задержкой. Мы
// кладём его в журнал Dkx, откуда владелец копирует его из настроек.
//
// Стек вызовов приходит без символов, только адреса и смещения в бинарниках.
// Расшифровать его можно по dSYM той же сборки.
@available(iOS 14.0, *)
final class DkxCrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DkxCrashReporter()

    // Стек бывает на десятки килобайт, журнал ограничен полумегабайтом
    private static let maxStackBytes = 40 * 1024

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var parts: [String] = []
                parts.append("сборка \(crash.metaData.applicationBuildVersion)")
                if let signal = crash.signal {
                    parts.append("сигнал \(signal)")
                }
                if let exceptionType = crash.exceptionType {
                    parts.append("исключение \(exceptionType)")
                }
                if let exceptionCode = crash.exceptionCode {
                    parts.append("код \(exceptionCode)")
                }
                if let reason = crash.terminationReason {
                    parts.append("причина \(reason)")
                }
                if #available(iOS 17.0, *), let objcReason = crash.exceptionReason {
                    parts.append("objc \(objcReason.exceptionName): \(objcReason.composedMessage)")
                }
                DkxLog.write("падение", parts.joined(separator: ", "))

                let stack = crash.callStackTree.jsonRepresentation()
                var stackText = String(decoding: stack.prefix(DkxCrashReporter.maxStackBytes), as: UTF8.self)
                if stack.count > DkxCrashReporter.maxStackBytes {
                    stackText += " …обрезано"
                }
                DkxLog.write("падение", "стек " + stackText.replacingOccurrences(of: "\n", with: " "))
            }
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                DkxLog.write("зависание", String(format: "%.1f с, сборка %@", seconds, hang.metaData.applicationBuildVersion))
            }
        }
    }
}
