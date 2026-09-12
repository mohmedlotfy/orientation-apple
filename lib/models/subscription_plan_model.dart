/// Subscription Plan Model representing plans available via GET /subscription-plans.
class SubscriptionPlanModel {
  final String id;
  final String name;
  final double price;
  final String currency;
  final String billingCycle;
  final List<String> features;
  final int sortOrder;
  final bool isPopular;

  SubscriptionPlanModel({
    required this.id,
    required this.name,
    required this.price,
    this.currency = 'EGP',
    this.billingCycle = 'month',
    this.features = const [],
    this.sortOrder = 0,
    this.isPopular = false,
  });

  factory SubscriptionPlanModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedFeatures = [];
    if (json['features'] is List) {
      parsedFeatures = (json['features'] as List)
          .map((item) => item.toString())
          .toList();
    } else if (json['features'] is String) {
      parsedFeatures = [json['features'].toString()];
    }

    final rawPrice = json['price'];
    double priceVal = 0.0;
    if (rawPrice is num) {
      priceVal = rawPrice.toDouble();
    } else if (rawPrice is String) {
      priceVal = double.tryParse(rawPrice) ?? 0.0;
    }

    return SubscriptionPlanModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: priceVal,
      currency: json['currency']?.toString() ?? 'EGP',
      billingCycle: json['billingCycle']?.toString() ?? json['interval']?.toString() ?? 'month',
      features: parsedFeatures,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isPopular: json['isPopular'] == true || json['popular'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'currency': currency,
      'billingCycle': billingCycle,
      'features': features,
      'sortOrder': sortOrder,
      'isPopular': isPopular,
    };
  }
}
