import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart';

/// A [LogOutput] that writes to [latestFileName] and rotates it once the file
/// exceeds [maxFileSizeKB].
///
/// Every isolate that logs — main, GlobalIsolate, IncrementalSyncIsolate, the
/// Android DartWorker — builds its own instance against the same file, so this
/// has to tolerate concurrent writers in one process:
///
///  * An event is written with a single [RandomAccessFile.writeFromSync]. The
///    handle is opened append-mode (O_APPEND), which makes one write atomic
///    against the other isolates; writing line by line let another isolate's
///    line land inside a multi-line event (stack traces, breadcrumb dumps).
///  * Rotation is decided from the file's real length and truncates in place.
///    A per-instance byte counter only ever saw its own writes, so every
///    instance rotated on a wrong total; worse, renaming left the other
///    isolates' handles on the rotated-away inode, so their lines silently
///    vanished from the file being collected. Truncating keeps the inode stable
///    for every writer — and since nothing is renamed while handles are open,
///    it also sidesteps the Windows errno 32 (ERROR_SHARING_VIOLATION) that the
///    close-before-rename dance existed to work around.
///
/// All failures are swallowed so the logger never crashes the app.
class RotatingFileOutput extends LogOutput {
  final String dirPath;
  final String latestFileName;
  final int maxFileSizeKB;
  final int maxRotatedFilesCount;
  final Encoding encoding;
  final String Function(DateTime) fileNameFormatter;

  File? _file;
  RandomAccessFile? _raf;

  RotatingFileOutput({
    required this.dirPath,
    required this.latestFileName,
    this.maxFileSizeKB = 1024,
    this.maxRotatedFilesCount = 5,
    this.encoding = utf8,
    required this.fileNameFormatter,
  });

  int get _maxBytes => maxFileSizeKB * 1024;

  @override
  Future<void> init() async {
    _openFile();
    // Clear out any NUL-filled shells left behind by the stale-position bug
    // described in [output], so they stop crowding out real history.
    _pruneOldFiles();
  }

  void _openFile() {
    try {
      _file = File(join(dirPath, latestFileName));
      if (!_file!.existsSync()) {
        _file!.createSync(recursive: true);
      }
      _raf = _file!.openSync(mode: FileMode.append);
    } catch (_) {
      _raf = null;
    }
  }

  @override
  void output(OutputEvent event) {
    final raf = _raf;
    if (raf == null || event.lines.isEmpty) return;
    try {
      // OpenBubbles: Dart's FileMode.append is NOT O_APPEND. It seeks to the end
      // once at open and then every handle tracks its own position, so with one
      // handle per isolate (main, GlobalIsolate, DartWorker) each writer clobbers
      // the others' lines, and after any isolate truncates the file for rotation
      // the rest keep writing at their old ~5 MB offsets. That produced sparse
      // files of NUL bytes that instantly looked oversized again, a rotation
      // storm, and an export with no history at all (2026-09-16). Re-seeking to
      // the real end before every write is the closest dart:io gets to append
      // semantics; two isolates logging in the same microsecond can still race,
      // which loses a line rather than the whole log.
      final bytes = encoding.encode('${event.lines.join('\n')}\n');
      final end = raf.lengthSync();
      raf.setPositionSync(end);
      // One write per event — never one per line. See the class doc.
      raf.writeFromSync(bytes);
      if (end + bytes.length >= _maxBytes) _rotate(raf);
    } catch (_) {}
  }

  void _rotate(RandomAccessFile raf) {
    try {
      // Another isolate may have rotated between our write and this check.
      if (raf.lengthSync() < _maxBytes) return;

      _file!.copySync(join(dirPath, fileNameFormatter(DateTime.now())));
      raf.truncateSync(0);
      // truncate does not move the position; without this the next write
      // from this handle would recreate the sparse file.
      raf.setPositionSync(0);
      _pruneOldFiles();
    } catch (_) {
      // Rotation must never crash the logger. The file stays oversized and we
      // retry on the next event, which is strictly better than losing lines.
    }
  }

  void _pruneOldFiles() {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;

      final rotated = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log') && !f.path.endsWith(latestFileName))
          .toList()
        ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

      // Shells from the stale-position bug: a rotated log whose leading bytes
      // are NUL holds no usable history, only padding. Drop them regardless of
      // count so they don't push real logs out of the retention window.
      rotated.removeWhere((f) {
        try {
          final raf = f.openSync();
          try {
            final head = raf.readSync(64);
            if (head.isNotEmpty && head.every((b) => b == 0)) {
              raf.closeSync();
              f.deleteSync();
              return true;
            }
          } finally {
            try { raf.closeSync(); } catch (_) {}
          }
        } catch (_) {}
        return false;
      });

      while (rotated.length > maxRotatedFilesCount) {
        try {
          rotated.removeAt(0).deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  Future<void> destroy() async {
    try {
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
  }
}
