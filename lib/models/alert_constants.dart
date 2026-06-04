class AlertLevel {
  static const red = 'RED';
  static const green = 'GREEN';

  static const labels = {
    red: 'Alert',
    green: 'Info',
  };
}

class AlertTarget {
  static const organization = 'organization';
  static const medic = 'medic';
  static const driver = 'driver';
  static const member = 'member';

  static const labels = {
    organization: 'Вся організація',
    medic: 'Медики',
    driver: 'Водії',
    member: 'Усі учасники',
  };
}
