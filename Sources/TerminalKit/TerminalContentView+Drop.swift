import AppKit

extension TerminalContentView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.droppedText(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let text = Self.droppedText(from: sender.draggingPasteboard) else {
            return false
        }
        DispatchQueue.main.async { [self] in
            paste(text: text)
        }
        return true
    }

    static func droppedText(from pasteboard: NSPasteboard) -> String? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let urls, !urls.isEmpty else {
            return pasteboard.string(forType: .string)
        }
        return urls.map { escapedPath($0.path(percentEncoded: false)) }.joined(separator: " ") + " "
    }

    static func escapedPath(_ path: String) -> String {
        String(
            String.UnicodeScalarView(
                path.unicodeScalars.flatMap { scalar -> [Unicode.Scalar] in
                    !scalar.isASCII || scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                        || "/._-+,@%:".unicodeScalars.contains(scalar)
                        || scalar.properties.generalCategory == .control && !scalar.properties.isWhitespace
                        ? [scalar] : ["\\", scalar]
                }
            )
        )
    }
}
