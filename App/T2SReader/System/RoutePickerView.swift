// App/T2SReader/System/RoutePickerView.swift
import AVKit
import SwiftUI

/// The system's AirPlay picker. It is the one control that can open the route list — there is no
/// API to present that list from a `Button` of our own — so the Cast sheet is built around it
/// rather than around a button that looks like it. Audio devices first: this is a reader, and a
/// TV is a speaker to it.
struct RoutePickerView: UIViewRepresentable {
    var tint: Color

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(tint)
    }
}
