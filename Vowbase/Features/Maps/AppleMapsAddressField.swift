import MapKit
import SwiftUI

@MainActor
struct AppleMapsAddressField: View {
    @Binding var text: String
    @Binding var selection: AppleMapsAddressSelection?
    let placeholder: String
    var onSubmit: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @StateObject private var search = AppleMapsAddressSearch()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { onSubmit?() }

                if search.isResolving {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if isFocused, !search.completions.isEmpty {
                Divider()
                    .padding(.top, 8)

                ForEach(Array(search.completions.enumerated()), id: \.offset) { index, completion in
                    Button {
                        select(completion)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(VowbaseTheme.rose)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel([completion.title, completion.subtitle]
                        .filter { !$0.isEmpty }
                        .joined(separator: ", "))

                    if index < search.completions.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .task(id: text) {
            if text != selection?.address {
                selection = nil
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            search.update(query: text)
        }
        .onChange(of: isFocused) { _, isFocused in
            onFocusChange?(isFocused)
        }
        .onDisappear { search.clear() }
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        Task {
            guard let selection = await search.resolve(completion) else { return }
            self.selection = selection
            text = selection.address
            isFocused = false
            search.clear()
        }
    }
}

/// A fully resolved Apple Maps result. Selected results carry their normalized
/// address, administrative fields, and MapKit coordinate together so callers
/// can persist one coherent location update.
struct AppleMapsAddressSelection: Equatable, Sendable {
    let address: String
    let city: String?
    let state: String?
    let country: String?
    let latitude: Double
    let longitude: Double
}

@MainActor
final class AppleMapsAddressSearch: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var completions = [MKLocalSearchCompletion]()
    @Published private(set) var isResolving = false

    private let completer: MKLocalSearchCompleter

    override init() {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        self.completer = completer
        super.init()
        completer.delegate = self
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            completions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.queryFragment = ""
        completions = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> AppleMapsAddressSelection? {
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled, let placemark = response.mapItems.first?.placemark,
                  let address = Self.streetAddress(
                streetNumber: placemark.subThoroughfare,
                streetName: placemark.thoroughfare,
                locality: placemark.locality,
                administrativeArea: placemark.administrativeArea,
                postalCode: placemark.postalCode,
                country: placemark.country
                  ), CLLocationCoordinate2DIsValid(placemark.coordinate) else { return nil }
            return AppleMapsAddressSelection(
                address: address,
                city: Self.nonblank(placemark.locality),
                state: Self.nonblank(placemark.administrativeArea),
                country: Self.nonblank(placemark.country),
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            )
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    nonisolated static func streetAddress(
        streetNumber: String?,
        streetName: String?,
        locality: String?,
        administrativeArea: String?,
        postalCode: String?,
        country: String?
    ) -> String? {
        let street = [streetNumber, streetName]
            .compactMap(Self.nonblank)
            .joined(separator: " ")
        guard !street.isEmpty else { return nil }

        let locality = Self.nonblank(locality)
        let regionAndPostalCode = [administrativeArea, postalCode]
            .compactMap(Self.nonblank)
            .joined(separator: " ")
        let localityLine: String
        if let locality, !regionAndPostalCode.isEmpty {
            localityLine = "\(locality), \(regionAndPostalCode)"
        } else {
            localityLine = locality ?? regionAndPostalCode
        }

        return [street, localityLine, country]
            .compactMap(Self.nonblank)
            .joined(separator: ", ")
    }

    nonisolated static func nonblank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = Array(completer.results.prefix(5))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
    }
}
