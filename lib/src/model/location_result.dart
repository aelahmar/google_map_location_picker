import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The result returned after completing location selection.
class LocationResult {
  LocationResult({
    this.formattedAddress,
    this.name,
    this.locality,
    this.latLng,
    this.street,
    this.country,
    this.state,
    this.city,
    this.zip,
  });

  String? formattedAddress;

  /// The human readable name of the location. This is primarily the
  /// name of the road. But in cases where the place was selected from Nearby
  /// places list, we use the <b>name</b> provided on the list item.
  String? name; // or road

  /// The human readable locality of the location.
  String? locality;

  /// The human readable sublocality of the location. (neighborhood)
  String? sublocality;

  /// Latitude/Longitude of the selected location.
  LatLng? latLng;

  String? street;

  String? country;

  String? state;

  String? city;

  String? zip;

  @override
  String toString() {
    return 'LocationResult{formattedAddress: $formattedAddress, name: $name, locality: $locality, latLng: $latLng, street: $street, country: $country, state: $state, city: $city, zip: $zip}';
  }
}
