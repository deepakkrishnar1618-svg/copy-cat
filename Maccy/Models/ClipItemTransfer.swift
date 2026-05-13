import SwiftUI

struct ClipItemTransfer: Transferable {
  let itemID: UUID

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation(
      exporting: { (t: ClipItemTransfer) -> String in t.itemID.uuidString },
      importing: { (s: String) -> ClipItemTransfer in
        ClipItemTransfer(itemID: UUID(uuidString: s) ?? UUID())
      }
    )
  }
}
