/// Park ids may contain `/` (e.g. `osm:way/123`) — use query, never raw path.
String parkDetailLocation(String parkId) =>
    Uri(path: '/park', queryParameters: {'id': parkId}).toString();
