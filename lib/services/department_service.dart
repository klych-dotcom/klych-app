import '../main.dart';

class DepartmentService {
  static const defaultNames = [
    'Headquarters',
    'Medics',
    'Drivers',
    'Logistics',
    'Communications',
    'Evacuation',
  ];

  /// Seeds default departments for a new organization. Returns Headquarters id.
  static Future<String?> seedDefaults(String organizationId) async {
    String? headquartersId;

    for (final name in defaultNames) {
      final row = await supabase
          .from('departments')
          .insert({
            'organization_id': organizationId,
            'name': name,
          })
          .select('id, name')
          .single();

      if (row['name'] == 'Headquarters') {
        headquartersId = row['id']?.toString();
      }
    }

    return headquartersId;
  }

  static Future<List<Map<String, dynamic>>> fetchActive(
    String organizationId,
  ) async {
    final rows = await supabase
        .from('departments')
        .select()
        .eq('organization_id', organizationId)
        .eq('is_archived', false)
        .order('name');

    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> fetchAll(
    String organizationId,
  ) async {
    final rows = await supabase
        .from('departments')
        .select()
        .eq('organization_id', organizationId)
        .order('name');

    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, dynamic>?> findByName({
    required String organizationId,
    required String name,
  }) async {
    final row = await supabase
        .from('departments')
        .select()
        .eq('organization_id', organizationId)
        .eq('name', name.trim())
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Creates a department or restores an archived one with the same name.
  static Future<Map<String, dynamic>> create({
    required String organizationId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Введіть назву підрозділу');
    }

    final existing = await findByName(
      organizationId: organizationId,
      name: trimmed,
    );

    if (existing != null) {
      if (existing['is_archived'] == true) {
        return restore(existing['id'].toString());
      }
      throw Exception('Підрозділ «$trimmed» вже існує');
    }

    final row = await supabase
        .from('departments')
        .insert({
          'organization_id': organizationId,
          'name': trimmed,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(row);
  }

  static Future<void> rename({
    required String departmentId,
    required String name,
    required String organizationId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Введіть назву підрозділу');
    }

    final existing = await findByName(
      organizationId: organizationId,
      name: trimmed,
    );

    if (existing != null && existing['id']?.toString() != departmentId) {
      throw Exception('Підрозділ «$trimmed» вже існує');
    }

    await supabase
        .from('departments')
        .update({'name': trimmed})
        .eq('id', departmentId);
  }

  static Future<void> archive(String departmentId) async {
    await supabase
        .from('departments')
        .update({'is_archived': true})
        .eq('id', departmentId);
  }

  static Future<Map<String, dynamic>> restore(String departmentId) async {
    final row = await supabase
        .from('departments')
        .update({'is_archived': false})
        .eq('id', departmentId)
        .select()
        .single();

    return Map<String, dynamic>.from(row);
  }
}
