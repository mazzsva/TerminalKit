import Foundation

func code(_ text: String) -> FourCharCode {
    text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
}

func type(_ text: String) -> NSAppleEventDescriptor {
    NSAppleEventDescriptor(typeCode: code(text))
}

func object(want: String, form: String, seld: NSAppleEventDescriptor, from: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
    let record = NSAppleEventDescriptor.record().coerce(toDescriptorType: code("obj "))!
    record.setDescriptor(type(want), forKeyword: code("want"))
    record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
    record.setDescriptor(seld, forKeyword: code("seld"))
    record.setDescriptor(from, forKeyword: code("from"))
    return record
}

func property(_ name: String, of parent: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
    object(want: "prop", form: "prop", seld: type(name), from: parent)
}

func window(index: Int32) -> NSAppleEventDescriptor {
    object(want: "cwin", form: "indx", seld: NSAppleEventDescriptor(int32: index), from: .null())
}

func window(id: Int32) -> NSAppleEventDescriptor {
    object(want: "cwin", form: "ID  ", seld: NSAppleEventDescriptor(int32: id), from: .null())
}

func tab(of parent: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
    object(want: "ttab", form: "indx", seld: NSAppleEventDescriptor(int32: 1), from: parent)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3, let processIdentifier = pid_t(arguments[1]) else {
    exit(2)
}
let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)

func send(
    _ eventClass: String,
    _ eventID: String,
    _ direct: NSAppleEventDescriptor,
    _ fill: (NSAppleEventDescriptor) -> Void = { _ in }
) throws -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
        eventClass: code(eventClass),
        eventID: code(eventID),
        targetDescriptor: target,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(direct, forKeyword: code("----"))
    fill(event)
    let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 30)
    if let number = reply.paramDescriptor(forKeyword: code("errn")), number.int32Value != 0 {
        throw NSError(domain: "ae", code: Int(number.int32Value))
    }
    return reply.paramDescriptor(forKeyword: code("----")) ?? .null()
}

func get(_ specifier: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
    try send("core", "getd", specifier)
}

func set(_ specifier: NSAppleEventDescriptor, _ value: NSAppleEventDescriptor) throws {
    _ = try send("core", "setd", specifier) { $0.setParam(value, forKeyword: code("data")) }
}

func windowCount() throws -> Int32 {
    try send("core", "cnte", .null()) { $0.setParam(type("cwin"), forKeyword: code("kocl")) }.int32Value
}

do {
    switch arguments[2] {
    case "find":
        for index in 1 ... max(try windowCount(), 1) {
            let current = window(index: index)
            if try get(property("ttty", of: tab(of: current))).stringValue == arguments[3] {
                print(try get(property("ID  ", of: current)).int32Value)
                exit(0)
            }
        }
        exit(4)
    case "hide":
        for index in 1 ... max(try windowCount(), 1) {
            try set(property("pvis", of: window(index: index)), NSAppleEventDescriptor(boolean: false))
        }
    case "size":
        let owned = window(id: Int32(arguments[3])!)
        if try get(property("pzum", of: owned)).booleanValue {
            try set(property("pzum", of: owned), NSAppleEventDescriptor(boolean: false))
        }
        let current = tab(of: owned)
        try set(property("ccol", of: current), NSAppleEventDescriptor(int32: Int32(arguments[4])!))
        try set(property("crow", of: current), NSAppleEventDescriptor(int32: Int32(arguments[5])!))
    case "read":
        let current = tab(of: window(id: Int32(arguments[3])!))
        var values: [String] = []
        for name in ["pcnt", "hist", "titl"] {
            values.append(try get(property(name, of: current)).stringValue ?? "")
        }
        FileHandle.standardOutput.write(Data(values.joined(separator: "\u{1}").utf8))
    default:
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
