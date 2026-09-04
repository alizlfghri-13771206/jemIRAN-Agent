import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/widgets/agent_activity_label.dart';

void main() {
  test('هر وضعیت از رخداد واقعی موتور متن مناسب می‌گیرد', () {
    expect(agentActivityLabel(AgentPhase.thinking), 'در حال فکر کردن');
    expect(agentActivityLabel(AgentPhase.planning), 'در حال برنامه‌ریزی');
    expect(
      agentActivityLabel(
        AgentPhase.executing,
        action: r'خواندن فایل · C:\project\lib\main.dart',
      ),
      r'در حال خواندن فایل · C:\project\lib\main.dart',
    );
    expect(agentActivityLabel(AgentPhase.observing), 'در حال بررسی نتیجه');
    expect(agentActivityLabel(AgentPhase.verifying), 'در حال راستی‌آزمایی');
  });

  test('اجازه و پاسخ کاربر با اجرای ابزار اشتباه گرفته نمی‌شوند', () {
    expect(
      agentActivityLabel(
        AgentPhase.awaitingPermission,
        action: 'ویرایش فایل · main.dart',
      ),
      'منتظر اجازه برای ویرایش فایل · main.dart',
    );
    expect(agentActivityLabel(AgentPhase.awaitingAnswer), 'منتظر پاسخ شما');
  });
}
