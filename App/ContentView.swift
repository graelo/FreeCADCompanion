//
//  ContentView.swift
//  FreeCADThumbnailPreview
//
//  Created by graelo.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Your logo (from Assets)
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .padding(.top, 32)
            
            // App name and version
            Text("FreeCAD Thumbnail Preview")
                .font(.title)
                .fontWeight(.bold)
            
            // Version info (optional)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Developer info
            Text("Made with ❤️ by graelo")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // .background(Color(.systemBackground))
    }
}

struct ContentView: View {
    
    var body: some View {
        VStack {
            AboutView()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
