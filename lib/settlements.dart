import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'family_shops.dart';

String normalizeSettlement(String value) => value.trim().toLowerCase()
    .replaceFirst(RegExp(r'^(?:м\.\s*|с\.\s*|смт\.?\s+|місто\s+|село\s+|селище\s+)'), '')
    .replaceAll(RegExp('[’ʼ`‘]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ').trim();

class Settlement {
  const Settlement(this.id, this.point, this.capital);
  final int id;
  final LatLng point;
  final bool capital;
}

/// An offline gazetteer of settlement centres. No device or household location.
class SettlementIndex {
  SettlementIndex.fromRows(List<dynamic> rows) {
    for (final row in rows) {
      final place = Settlement(row[0] as int,
          LatLng((row[1] as num).toDouble(), (row[2] as num).toDouble()), row[3] == 0);
      for (final name in row[4] as List) {
        final key = normalizeSettlement(name as String);
        (_names[key] ??= {})[place.id] = place;
      }
    }
  }

  final _names = <String, Map<int, Settlement>>{};

  static Future<SettlementIndex> load() async => SettlementIndex.fromRows(
      jsonDecode(await rootBundle.loadString('assets/places/ukraine.json')) as List);

  Settlement? resolve(String city) {
    final candidates = _names[normalizeSettlement(city)]?.values.toList() ?? [];
    if (candidates.length == 1) return candidates.single;
    // Bare regional-centre names refer to that city. Other homonyms stay unmapped.
    final capitals = candidates.where((place) => place.capital).toList();
    return capitals.length == 1 ? capitals.single : null;
  }
}

class ShopCity {
  ShopCity(this.place, this.label);
  final Settlement place;
  final String label;
  final shops = <String, PublicFamilyShop>{};
}

List<ShopCity> groupShopsByCity(List<PublicFamilyShop> shops, SettlementIndex index) {
  final cities = <int, ShopCity>{};
  for (final shop in shops) {
    for (final city in shop.cities) {
      final place = index.resolve(city);
      if (place == null) continue;
      (cities[place.id] ??= ShopCity(place, city.trim())).shops[shop.id] = shop;
    }
  }
  return cities.values.toList()..sort((a, b) => a.label.compareTo(b.label));
}
