import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_map_location_picker/generated/l10n.dart';
import 'package:google_map_location_picker/src/map.dart';
import 'package:google_map_location_picker/src/providers/location_provider.dart';
import 'package:google_map_location_picker/src/rich_suggestion.dart';
import 'package:google_map_location_picker/src/search_input.dart';
import 'package:google_map_location_picker/src/utils/uuid.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'model/auto_comp_iete_item.dart';
import 'model/location_result.dart';
import 'model/nearby_place.dart';
import 'utils/location_utils.dart';

class LocationPicker extends StatefulWidget {
  LocationPicker(
    this.apiKey, {
    Key? key,
    this.initialCenter,
    this.initialZoom,
    this.requiredGPS,
    this.myLocationButtonEnabled,
    this.layersButtonEnabled,
    this.automaticallyAnimateToCurrentLocation,
    this.mapStylePath,
    this.appBarColor,
    this.searchBarBoxDecoration,
    this.hintText,
    this.resultCardConfirmIcon,
    this.resultCardAlignment,
    this.resultCardDecoration,
    this.resultCardPadding,
    this.countries,
    this.language,
    this.desiredAccuracy,
  });

  final String apiKey;

  final LatLng? initialCenter;
  final double? initialZoom;
  final List<String>? countries;

  final bool? requiredGPS;
  final bool? myLocationButtonEnabled;
  final bool? layersButtonEnabled;
  final bool? automaticallyAnimateToCurrentLocation;

  final String? mapStylePath;

  final Color? appBarColor;
  final BoxDecoration? searchBarBoxDecoration;
  final String? hintText;
  final Widget? resultCardConfirmIcon;
  final Alignment? resultCardAlignment;
  final Decoration? resultCardDecoration;
  final EdgeInsets? resultCardPadding;

  final String? language;

  final LocationAccuracy? desiredAccuracy;

  @override
  LocationPickerState createState() => LocationPickerState();
}

class LocationPickerState extends State<LocationPicker> {
  /// Result returned after user completes selection
  LocationResult? locationResult;

  /// Overlay to display autocomplete suggestions
  OverlayEntry? overlayEntry;

  List<NearbyPlace> nearbyPlaces = [];

  /// Session token required for autocomplete API call
  String sessionToken = Uuid().generateV4();

  var mapKey = GlobalKey<MapPickerState>();

  var appBarKey = GlobalKey();

  var searchInputKey = GlobalKey<SearchInputState>();

  bool hasSearchTerm = false;

  /// Hides the autocomplete overlay
  void clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry!.remove();
      overlayEntry = null;
    }
  }

  /// Begins the search process by displaying a "wait" overlay then
  /// proceeds to fetch the autocomplete list. The bottom "dialog"
  /// is hidden so as to give more room and better experience for the
  /// autocomplete list overlay.
  void searchPlace(String place) {
    clearOverlay();

    setState(() => hasSearchTerm = place.length > 0);

    if (place.length < 1) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    Size size = renderBox.size;

    final RenderBox? appBarBox =
        appBarKey.currentContext!.findRenderObject() as RenderBox?;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarBox!.size.height,
        width: size.width,
        child: Material(
          elevation: 1,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              children: <Widget>[
                SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(width: 24),
                Expanded(
                  child: Text(
                    S.of(context).finding_place,
                    style: TextStyle(fontSize: 16),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context)!.insert(overlayEntry!);

    autoCompleteSearch(place);
  }

  /// Fetches the place autocomplete list with the query [place].
  void autoCompleteSearch(String place) async {
    place = place.replaceAll(" ", "+");

    final countries = widget.countries;

    // Currently, you can use components to filter by up to 5 countries. from https://developers.google.com/places/web-service/autocomplete
    String regionParam = countries?.isNotEmpty == true
        ? "&components=country:${countries!.sublist(0, min(countries.length, 5)).join('|country:')}"
        : "";

    var endpoint =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?" +
            "key=${widget.apiKey}&" +
            "input={$place}$regionParam&sessiontoken=$sessionToken&" +
            "language=${widget.language}";

    if (locationResult != null) {
      endpoint += "&location=${locationResult!.latLng!.latitude}," +
          "${locationResult!.latLng!.longitude}";
    }

    final headers = await LocationUtils.getAppHeaders();
    final response = await http.get(Uri.parse(endpoint), headers: headers);

    if (response.statusCode == 200) {
      Map<String, dynamic> data = jsonDecode(response.body);
      List<dynamic> predictions = data['predictions'];

      List<RichSuggestion> suggestions = [];

      if (predictions.isEmpty) {
        AutoCompleteItem aci = AutoCompleteItem();
        aci.text = S.of(context).no_result_found;
        aci.offset = 0;
        aci.length = 0;

        suggestions.add(RichSuggestion(aci, () {}));
      } else {
        for (dynamic t in predictions) {
          AutoCompleteItem aci = AutoCompleteItem();

          aci.id = t['place_id'];
          aci.text = t['description'];
          aci.offset = t['matched_substrings'][0]['offset'];
          aci.length = t['matched_substrings'][0]['length'];

          suggestions.add(RichSuggestion(aci, () {
            decodeAndSelectPlace(aci.id);
          }));
        }
      }

      displayAutoCompleteSuggestions(suggestions);
    }
  }

  /// To navigate to the selected place from the autocomplete list to the map,
  /// the lat,lng is required. This method fetches the lat,lng of the place and
  /// proceeds to moving the map to that location.
  void decodeAndSelectPlace(String? placeId) {
    clearOverlay();

    final endpoint =
        "https://maps.googleapis.com/maps/api/place/details/json?key=${widget.apiKey}" +
            "&placeid=$placeId" +
            '&language=${widget.language}';

    LocationUtils.getAppHeaders()
        .then((headers) => http.get(Uri.parse(endpoint), headers: headers))
        .then((response) {
      if (response.statusCode == 200) {
        Map<String, dynamic> location =
            jsonDecode(response.body)['result']['geometry']['location'];

        LatLng latLng = LatLng(location['lat'], location['lng']);

        moveToLocation(latLng);
      }
    }).catchError((error) {
      print(error);
    });
  }

  /// Display autocomplete suggestions with the overlay.
  void displayAutoCompleteSuggestions(List<RichSuggestion> suggestions) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    Size size = renderBox.size;

    final RenderBox? appBarBox =
        appBarKey.currentContext!.findRenderObject() as RenderBox?;

    clearOverlay();

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        top: appBarBox!.size.height,
        child: Material(
          elevation: 1,
          child: Column(
            children: suggestions,
          ),
        ),
      ),
    );

    Overlay.of(context)!.insert(overlayEntry!);
  }

  /// Utility function to get clean readable name of a location. First checks
  /// for a human-readable name from the nearby list. This helps in the cases
  /// that the user selects from the nearby list (and expects to see that as a
  /// result, instead of road name). If no name is found from the nearby list,
  /// then the road name returned is used instead.
//  String getLocationName() {
//    if (locationResult == null) {
//      return "Unnamed location";
//    }
//
//    for (NearbyPlace np in nearbyPlaces) {
//      if (np.latLng == locationResult.latLng) {
//        locationResult.name = np.name;
//        return np.name;
//      }
//    }
//
//    return "${locationResult.name}, ${locationResult.locality}";
//  }

  /// Fetches and updates the nearby places to the provided lat,lng
  void getNearbyPlaces(LatLng latLng) {
    LocationUtils.getAppHeaders().then((headers) {
      var endpoint =
          "https://maps.googleapis.com/maps/api/place/nearbysearch/json?" +
              "key=${widget.apiKey}&" +
              "location=${latLng.latitude},${latLng.longitude}&radius=150" +
              "&language=${widget.language}";

      return http.get(Uri.parse(endpoint), headers: headers);
    }).then((response) {
      if (response.statusCode == 200) {
        nearbyPlaces.clear();
        for (Map<String, dynamic> item
            in jsonDecode(response.body)['results']) {
          NearbyPlace nearbyPlace = NearbyPlace();

          nearbyPlace.name = item['name'];
          nearbyPlace.icon = item['icon'];
          double latitude = item['geometry']['location']['lat'];
          double longitude = item['geometry']['location']['lng'];

          LatLng _latLng = LatLng(latitude, longitude);

          nearbyPlace.latLng = _latLng;

          nearbyPlaces.add(nearbyPlace);
        }
      }

      // to update the nearby places
      setState(() {
        // this is to require the result to show
        hasSearchTerm = false;
      });
    }).catchError((error) {});
  }

  /// This method gets the human readable name of the location. Mostly appears
  /// to be the road name and the locality.
  Future reverseGeocodeLatLng(LatLng latLng) async {
    final endpoint =
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}" +
            "&key=${widget.apiKey}" +
            "&language=${widget.language}";

    final response = await http.get(Uri.parse(endpoint),
        headers: await (LocationUtils.getAppHeaders()));

    Map<String, dynamic> responseJson = jsonDecode(response.body);
    if (response.statusCode == 200 &&
        responseJson['results'] is List &&
        List.from(responseJson['results']).isNotEmpty) {
      String? road = '';
      String? locality = '';

      String? number = '';
      String? street = '';
      String? state = '';

      String? city = '';
      String? country = '';
      String? zip = '';

      List components = responseJson['results'][0]['address_components'];
      for (var i = 0; i < components.length; i++) {
        final item = components[i];
        List types = item['types'];
        if (types.contains('street_number') ||
            types.contains('premise') ||
            types.contains('sublocality') ||
            types.contains('sublocality_level_2')) {
          if (number!.isEmpty) {
            number = item['long_name'];
          }
        }
        if (types.contains('route') || types.contains('neighborhood')) {
          if (street!.isEmpty) {
            street = item['long_name'];
          }
        }
        if (types.contains('administrative_area_level_1')) {
          state = item['short_name'];
        }
        if (types.contains('administrative_area_level_2') ||
            types.contains('administrative_area_level_3')) {
          if (city!.isEmpty) {
            city = item['long_name'];
          }
        }
        if (types.contains('locality')) {
          if (locality!.isEmpty) {
            locality = item['short_name'];
          }
        }
        if (types.contains('route')) {
          if (road!.isEmpty) {
            road = item['long_name'];
          }
        }
        if (types.contains('country')) {
          country = item['short_name'];
          if (types.contains('postal_code')) {
            if (zip!.isEmpty) {
              zip = item['long_name'];
            }
          }
        }

        setState(() {
          locationResult = LocationResult();
          locationResult!.name = road;
          locationResult!.locality = locality;
          locationResult!.latLng = latLng;
          locationResult!.street = '$number $street';
          locationResult!.state = state;
          locationResult!.city = city;
          locationResult!.country = country;
          locationResult!.zip = zip;
        });
      }
    } else {
      setState(() {
        locationResult = LocationResult();
        locationResult!.name = '';
        locationResult!.latLng = latLng;
        locationResult!.street = '';
        locationResult!.state = '';
        locationResult!.city = '';
        locationResult!.country = '';
        locationResult!.zip = '';
      });
    }
  }

  /// Moves the camera to the provided location and updates other UI features to
  /// match the location.
  void moveToLocation(LatLng latLng) {
    mapKey.currentState!.mapController.future.then((controller) {
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 16,
          ),
        ),
      );
    });

    reverseGeocodeLatLng(latLng);

    // getNearbyPlaces(latLng);
  }

  @override
  void dispose() {
    clearOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: Builder(builder: (context) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            iconTheme: Theme.of(context).iconTheme.copyWith(
                  color: Colors.white,
                ),
            elevation: 0,
            backgroundColor: widget.appBarColor,
            key: appBarKey,
            title: Visibility(
              visible: false,
              child: SearchInput(
                (input) => searchPlace(input),
                key: searchInputKey,
                boxDecoration: widget.searchBarBoxDecoration,
                hintText: widget.hintText,
              ),
            ),
          ),
          body: MapPicker(
            widget.apiKey,
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            requiredGPS: widget.requiredGPS,
            myLocationButtonEnabled: widget.myLocationButtonEnabled,
            layersButtonEnabled: widget.layersButtonEnabled,
            automaticallyAnimateToCurrentLocation:
                widget.automaticallyAnimateToCurrentLocation,
            mapStylePath: widget.mapStylePath,
            appBarColor: widget.appBarColor,
            searchBarBoxDecoration: widget.searchBarBoxDecoration,
            hintText: widget.hintText,
            resultCardConfirmIcon: widget.resultCardConfirmIcon,
            resultCardAlignment: widget.resultCardAlignment,
            resultCardDecoration: widget.resultCardDecoration,
            resultCardPadding: widget.resultCardPadding,
            key: mapKey,
            language: widget.language,
            desiredAccuracy: widget.desiredAccuracy,
          ),
        );
      }),
    );
  }
}

/// Returns a [LatLng] object of the location that was picked.
///
/// The [apiKey] argument API key generated from Google Cloud Console.
/// You can get an API key [here](https://cloud.google.com/maps-platform/)
///
/// [initialCenter] The geographical location that the camera is pointing
/// until the current user location is know if you want to change this
/// set [automaticallyAnimateToCurrentLocation] to false.
///
///
Future<LocationResult?> showLocationPicker(
  BuildContext context,
  String apiKey, {
  LatLng initialCenter = const LatLng(45.521563, -122.677433),
  double initialZoom = 16,
  bool requiredGPS = false,
  List<String>? countries,
  bool myLocationButtonEnabled = false,
  bool layersButtonEnabled = false,
  bool automaticallyAnimateToCurrentLocation = true,
  String? mapStylePath,
  Color appBarColor = Colors.transparent,
  BoxDecoration? searchBarBoxDecoration,
  String? hintText,
  Widget? resultCardConfirmIcon,
  AlignmentGeometry? resultCardAlignment,
  EdgeInsetsGeometry? resultCardPadding,
  Decoration? resultCardDecoration,
  String language = 'en',
  LocationAccuracy desiredAccuracy = LocationAccuracy.best,
}) async {
  final results = await Navigator.of(context).push(
    MaterialPageRoute<dynamic>(
      builder: (BuildContext context) {
        // print('[LocationPicker] [countries] ${countries.join(', ')}');
        return LocationPicker(
          apiKey,
          initialCenter: initialCenter,
          initialZoom: initialZoom,
          requiredGPS: requiredGPS,
          myLocationButtonEnabled: myLocationButtonEnabled,
          layersButtonEnabled: layersButtonEnabled,
          automaticallyAnimateToCurrentLocation:
              automaticallyAnimateToCurrentLocation,
          mapStylePath: mapStylePath,
          appBarColor: appBarColor,
          hintText: hintText,
          searchBarBoxDecoration: searchBarBoxDecoration,
          resultCardConfirmIcon: resultCardConfirmIcon,
          resultCardAlignment: resultCardAlignment as Alignment?,
          resultCardPadding: resultCardPadding as EdgeInsets?,
          resultCardDecoration: resultCardDecoration,
          countries: countries,
          language: language,
          desiredAccuracy: desiredAccuracy,
        );
      },
    ),
  );

  if (results != null && results.containsKey('location')) {
    return results['location'];
  } else {
    return null;
  }
}
