class Listing {
  final String id, title, description, category, condition, dealType, city, status;
  final int? price;
  final String? photoPath;
  Listing.fromMap(Map<String, dynamic> m)
    : id = m['id'].toString(), title = m['title'] ?? '', description = m['description'] ?? '',
      category = m['category'] ?? 'Інше', condition = m['condition'] ?? 'used',
      dealType = m['deal_type'] ?? 'gift', city = m['city'] ?? '',
      status = m['status'] ?? 'pending', price = m['price'] as int?,
      photoPath = m['photo_path'] as String?;
}

