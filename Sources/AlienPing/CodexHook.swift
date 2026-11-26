import Foundation
import AlienCore

enum CodexHook {
    static func run() throws {
        let input=FileHandle.standardInput.readDataToEndOfFile()
        let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Psst/codex-events")
        let defaults=UserDefaults(suiteName:"local.alienping.mac")
        if defaults?.object(forKey:"enabled") as? Bool == false { return }
        try record(input,in:directory,keepText:defaults?.bool(forKey:"storeInboxContent") == true)
    }
    static func record(_ input:Data,in directory:URL,keepText:Bool) throws {
        guard let event=try? JSONDecoder().decode(CodexUpdate.self,from:input),
              var entry=event.entry() else { return }
        if !keepText { entry.body="";entry.title="" }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let file=directory.appendingPathComponent(entry.id.uuidString.lowercased()+".json")
        try JSONEncoder().encode(entry).write(to:file,options:.atomic)
    }
}
