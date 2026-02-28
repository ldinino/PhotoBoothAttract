//
//  GuestView.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI

struct GuestView: View {
    @EnvironmentObject var photoManager: PhotoManager
    
    // Define a flexible 2-column grid
    let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                let topFour = Array(photoManager.photos.prefix(4))
                
                if topFour.isEmpty {
                    Text("Waiting for photos...")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.gray)
                } else {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(Array(topFour.enumerated()), id: \.element.id) { index, photo in
                            GuestPhotoCell(photo: photo, number: index + 1)
                                .frame(height: geometry.size.height / 2) // Half the screen height per row
                                .clipped()
                        }
                    }
                }
            }
        }
    }
}

struct GuestPhotoCell: View {
    let photo: PhotoModel
    let number: Int
    
    var body: some View {
        ZStack {
            Image(nsImage: photo.thumbnail)
                .resizable()
                .scaledToFill() // Fill the grid cell entirely
            
            // High-contrast number overlay
            VStack {
                HStack {
                    Text("\(number)")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        // Heavy shadow for contrast against bright photos
                        .shadow(color: .black.opacity(0.8), radius: 8, x: 4, y: 4)
                        .padding(40)
                    
                    Spacer()
                }
                Spacer()
            }
        }
        // Inner border to separate the grid slightly
        .border(Color.black, width: 4)
    }
}
