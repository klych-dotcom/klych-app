/// UI-only Ukrainian labels for seeded department names (DB values unchanged).
class DepartmentLabels {
  static const _labels = {
    'Headquarters': 'Штаб',
    'Medics': 'Медики',
    'Drivers': 'Водії',
    'Logistics': 'Логістика',
    'Communications': 'Зв\'язок',
  };

  static String localize(String? name) {
    if (name == null || name.isEmpty) return '—';
    return _labels[name] ?? name;
  }
}
