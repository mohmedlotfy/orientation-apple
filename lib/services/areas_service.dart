import '../models/area_model.dart';

/// Areas Service providing static catalog of discover areas with zero network requests.
class AreasService {
  static final List<AreaModel> _staticAreas = [
    AreaModel(
      id: 'new_cairo',
      name: 'New Cairo',
      image: 'assets/images/areas/new_cairo.jpg',
      isAsset: true,
      projectsCount: 45,
    ),
    AreaModel(
      id: 'sheikh_zayed',
      name: 'Sheikh Zayed',
      image: 'assets/images/areas/sheikh_zayed.jpg',
      isAsset: true,
      projectsCount: 38,
    ),
    AreaModel(
      id: 'new_capital',
      name: 'New Capital',
      image: 'assets/images/areas/new_capital.jpg',
      isAsset: true,
      projectsCount: 52,
    ),
    AreaModel(
      id: 'north_coast',
      name: 'North Coast',
      image: 'assets/images/areas/north_coast.jpg',
      isAsset: true,
      projectsCount: 29,
    ),
    AreaModel(
      id: 'mostakbal_city',
      name: 'Mostakbal City',
      image: 'assets/images/areas/mostakbal_city.jpg',
      isAsset: true,
      projectsCount: 24,
    ),
    AreaModel(
      id: 'ain_sokhna',
      name: 'Ain Sokhna',
      image: 'assets/images/areas/ain_sokhna.jpg',
      isAsset: true,
      projectsCount: 20,
    ),
    AreaModel(
      id: '6th_october',
      name: '6th of October',
      image: 'assets/images/areas/6th_october.jpg',
      isAsset: true,
      projectsCount: 35,
    ),
    AreaModel(
      id: 'shorouk',
      name: 'El Shorouk',
      image: 'assets/images/areas/shorouk.jpg',
      isAsset: true,
      projectsCount: 18,
    ),
    AreaModel(
      id: 'heliopolis',
      name: 'Heliopolis',
      image: 'assets/images/areas/heliopolis.jpg',
      isAsset: true,
      projectsCount: 15,
    ),
    AreaModel(
      id: 'maadi',
      name: 'Maadi',
      image: 'assets/images/areas/maadi.jpg',
      isAsset: true,
      projectsCount: 16,
    ),
    AreaModel(
      id: 'red_sea',
      name: 'Red Sea / Gouna',
      image: 'assets/images/areas/red_sea.jpg',
      isAsset: true,
      projectsCount: 22,
    ),
  ];

  /// Returns static list of 11 areas instantly.
  static List<AreaModel> getAreas() => List.unmodifiable(_staticAreas);

  /// Returns an area by ID if found.
  static AreaModel? getAreaById(String id) {
    try {
      return _staticAreas.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }
}
