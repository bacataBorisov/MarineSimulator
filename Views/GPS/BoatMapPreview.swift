struct BoatMapPreview: View {
    var coordinate: CLLocationCoordinate2D
    @State private var mapPosition: MapCameraPosition = .automatic
    
    var body: some View {
        Map(position: $mapPosition) {
            Annotation("Boat", coordinate: coordinate) {
                Image(systemName: "sailboat.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            mapPosition = .camera(MapCamera(centerCoordinate: coordinate, distance: 200000))
        }
        .disabled(true) // prevent interaction for preview
    }
}
