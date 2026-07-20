import Foundation

/// Writes a line to standard error. Lives in Core so both the macOS CLI and the
/// iOS target (which compiles Core without `main.swift`) can use it.
func errPrint(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}
