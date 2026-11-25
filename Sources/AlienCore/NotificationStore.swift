import Foundation
import SQLite3

/// A small transactional store for the bounded (200-item) local tray.
public final class NotificationStore {
    private var db:OpaquePointer?
    public let url:URL
    public init(directory:URL,storeContent:Bool) throws {
        url=directory.appendingPathComponent("notifications.sqlite")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard sqlite3_open(url.path,&db)==SQLITE_OK else { let e=failure();sqlite3_close(db);db=nil;throw e }
        do {
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            sqlite3_busy_timeout(db,2000)
            try execute("PRAGMA journal_mode=DELETE; PRAGMA secure_delete=ON; CREATE TABLE IF NOT EXISTS inbox (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
            let legacy=directory.appendingPathComponent("inbox.json")
            if try payload()==nil {
                var initial=InboxState()
                if FileManager.default.fileExists(atPath:legacy.path) { initial=try JSONDecoder().decode(InboxState.self,from:Data(contentsOf:legacy)) }
                initial.prune()
                try save(initial,storeContent:storeContent)
            }
            // The committed singleton also marks migration complete, even after clearing the tray.
            if FileManager.default.fileExists(atPath:legacy.path) { try FileManager.default.removeItem(at:legacy) }
        } catch { sqlite3_close(db);db=nil;throw error }
    }
    deinit { sqlite3_close(db) }
    private func failure()->NSError { NSError(domain:"Psst.NotificationStore",code:Int(sqlite3_errcode(db)),userInfo:[NSLocalizedDescriptionKey:String(cString:sqlite3_errmsg(db))]) }
    private func execute(_ sql:String) throws { guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else { throw failure() } }
    private func payload() throws -> Data? {
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT payload FROM inbox WHERE id=1",-1,&statement,nil)==SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_DONE:return nil
        case SQLITE_ROW:
            guard let bytes=sqlite3_column_blob(statement,0) else { throw failure() }
            return Data(bytes:bytes,count:Int(sqlite3_column_bytes(statement,0)))
        default:throw failure()
        }
    }
    public func load() throws -> InboxState {
        guard let data=try payload() else { return InboxState() }
        var state=try JSONDecoder().decode(InboxState.self,from:data);state.prune();return state
    }
    public func save(_ state:InboxState,storeContent:Bool) throws {
        let data=try state.encoded(storeContent:storeContent)
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"INSERT OR REPLACE INTO inbox(id,payload) VALUES(1,?)",-1,&statement,nil)==SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let bound=data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement,1,bytes.baseAddress,Int32(bytes.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
        guard bound==SQLITE_OK,sqlite3_step(statement)==SQLITE_DONE else { throw failure() }
    }
}
