/// 「编程预置词」页面 Widget 测试：
/// - 三态：loading / 空状态 / 列表数据；请求失败展示错误+重试
/// - 新增弹框：名称必填、名称唯一性、内容 300 字上限、保存成功刷新
/// - 编辑与新增共用弹框（回填 + 保存更新）
/// - 删除：二次确认，取消不删、确认后删
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/preset_page.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

/// 首拉失败存储：loadPresets 首次抛错，验证错误态与重试
class _FailingStorage extends SqliteStorage {
  _FailingStorage() : super(sqlite3.openInMemory());
  bool failNextLoad = true;

  @override
  Future<List<CodingPreset>> loadPresets() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw Exception('网络异常');
    }
    return super.loadPresets();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    appState = await makeTestAppState();
  });

  Future<void> pumpPage(WidgetTester tester, {double w = 1280}) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const PresetPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('列表三态', () {
    testWidgets('无数据 → 空状态占位文案', (tester) async {
      await pumpPage(tester);
      expect(find.textContaining('暂无编程预置词'), findsOneWidget);
    });

    testWidgets('有数据 → 四列表头与行内容', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: 'Electron + Vue3', createdAt: 1700000000));
      await pumpPage(tester);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
      expect(find.text('创建日期'), findsOneWidget);
      expect(find.text('操作'), findsOneWidget);
      expect(find.text('桌面端'), findsOneWidget);
      expect(find.text('Electron + Vue3'), findsOneWidget);
    });

    testWidgets('请求失败 → 错误信息 + 重试', (tester) async {
      // init 需成功；init 后再让下一次（页面首拉）失败
      final st = _FailingStorage()..failNextLoad = false;
      appState = await makeTestAppState(storage: st);
      st.failNextLoad = true;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrapWithFluentApp(const PresetPage()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 重试成功后恢复正常
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('加载失败'), findsNothing);
      expect(find.textContaining('暂无编程预置词'), findsOneWidget);
    });
  });

  group('新增/编辑弹框', () {
    testWidgets('名称为空 → 提交拦截提示', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('＋ 新增'));
      await tester.pumpAndSettle();
      // 只填内容不填名称
      await tester.enterText(find.byType(TextBox).at(1), '技术背景内容');
      await tester.pump();
      await tester.tap(find.text('新增'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('名称不能为空'), findsOneWidget);
      expect(find.text('新增预置词'), findsOneWidget, reason: '校验失败弹框不关闭');
    });

    testWidgets('名称重复 → 唯一性拦截提示', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: '已有内容', createdAt: 1700000000));
      await pumpPage(tester);
      await tester.tap(find.text('＋ 新增'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).at(0), ' 桌面端 ');
      await tester.enterText(find.byType(TextBox).at(1), '新内容');
      await tester.pump();
      await tester.tap(find.text('新增'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('已存在'), findsOneWidget);
    });

    testWidgets('内容 300 字上限：输入被限制 + 保存成功刷新列表', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('＋ 新增'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).at(0), '长内容');
      await tester.enterText(find.byType(TextBox).at(1), '字' * 300);
      await tester.pump();
      // 字数计数器显示 300/300
      expect(find.text('300/300'), findsOneWidget);
      await tester.tap(find.text('新增'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // 弹框已关闭，列表刷新出现新条目
      expect(find.text('新增预置词'), findsNothing);
      expect(find.text('长内容'), findsOneWidget);
    });

    testWidgets('编辑共用弹框：回填旧值并保存更新', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: '旧内容', createdAt: 1700000000));
      await pumpPage(tester);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      // 弹框为编辑态且回填（限定弹框内匹配，避免与列表行文本重名）
      expect(find.text('编辑预置词'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('preset-dialog-panel')),
              matching: find.text('旧内容')),
          findsOneWidget);
      await tester.enterText(find.byType(TextBox).at(1), '更新后的内容');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('更新后的内容'), findsOneWidget);
      expect(find.text('旧内容'), findsNothing);
      expect(find.text('桌面端'), findsOneWidget, reason: '名称未改保持不变');
    });
  });

  group('删除二次确认', () {
    testWidgets('取消 → 不删除', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: '内容', createdAt: 1700000000));
      await pumpPage(tester);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定删除'), findsOneWidget);
      await tester.tap(find.widgetWithText(Button, '取消'));
      await tester.pumpAndSettle();
      expect(find.text('桌面端'), findsOneWidget);
    });

    testWidgets('确认 → 删除并刷新', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: '内容', createdAt: 1700000000));
      await pumpPage(tester);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 5)); // 排空 InfoBar Timer
      await tester.pumpAndSettle();
      expect(find.text('桌面端'), findsNothing);
      expect(find.textContaining('暂无编程预置词'), findsOneWidget);
    });
  });
}
