/// native：系统原生保存对话框（file_selector，用户硬性要求）
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../services/export_service.dart';

class NativeFileSaver implements FileSaver {
  const NativeFileSaver();

  @override
  Future<String?> save({
    required String suggestedName,
    required String ext,
    required List<int> bytes,
  }) async {
    final loc = await getSaveLocation(
      suggestedName: '$suggestedName.$ext',
      acceptedTypeGroups: [
        XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
      ],
    );
    if (loc == null) return null; // 用户取消
    await XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType: ext == 'json' ? 'application/json' : 'text/plain',
      name: '$suggestedName.$ext',
    ).saveTo(loc.path);
    return loc.path;
  }

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(
          label: extensions.map((e) => e.toUpperCase()).join('/'),
          extensions: extensions),
    ]);
    if (file == null) return null; // 用户取消
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }
}

FileSaver createFileSaver() => const NativeFileSaver();
