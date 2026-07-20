import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_event.dart';

abstract interface class AnalyticsEventStore {
  Future<List<AnalyticsEvent>> load();

  Future<void> save(List<AnalyticsEvent> events);
}

class SharedPreferencesAnalyticsEventStore implements AnalyticsEventStore {
  SharedPreferencesAnalyticsEventStore({
    SharedPreferencesAsync? preferences,
    this.key = 'company_analytics.pending_events',
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  final String key;

  @override
  Future<List<AnalyticsEvent>> load() async {
    final encoded = await _preferences.getString(key);
    if (encoded == null) {
      return <AnalyticsEvent>[];
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! List<Object?>) {
      throw const FormatException('Pending analytics events must be a list.');
    }
    return decoded
        .map((item) => AnalyticsEvent.fromJson(item as Map<String, Object?>))
        .toList(growable: false);
  }

  @override
  Future<void> save(List<AnalyticsEvent> events) async {
    if (events.isEmpty) {
      await _preferences.remove(key);
      return;
    }
    await _preferences.setString(
      key,
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }
}
