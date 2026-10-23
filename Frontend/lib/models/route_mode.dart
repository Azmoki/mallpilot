/// How the user wants to travel through the stop list.
/// This is the "contract" between the Stop List page and the navigation part.
enum RouteMode {
  sequence, // follow the order the user arranged
  shortest, // reorder the stops so the walk is as short as possible
}
