/// web：浏览器下载
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

import '../../services/export_service.dart';

class WebFileSaver implements FileSaver {
  const WebFileSaver();

  @override
  Future<String?> save({
    required String suggestedName,
    required String ext,
    required List<int> bytes,
  }) async {
    final name = '$suggestedName.$ext';
    final blob = web.Blob(
      [utf8.decode(bytes).toJS].toJS,
      web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = name;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return name; // 浏览器下载路径由浏览器决定，返回文件名作为凭证
  }

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(
          label: extensions.map((e) => e.toUpperCase()).join('/'),
          extensions: extensions),
    ]);
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }
}

FileSaver createFileSaver() => const WebFileSaver();
