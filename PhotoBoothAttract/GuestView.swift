//
//  GuestView.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI

struct GuestView: View {
    @EnvironmentObject var photoManager: PhotoManager

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 2
            let cellHeight = geometry.size.height / 2
            let topFour = Array(photoManager.photos.prefix(4))

            ZStack {
                Color.black.ignoresSafeArea()

                if topFour.isEmpty {
                    Text("Waiting for photos...")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.gray)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            if topFour.count > 0 {
                                GuestPhotoCell(photo: topFour[0], number: 1)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                            if topFour.count > 1 {
                                GuestPhotoCell(photo: topFour[1], number: 2)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                        HStack(spacing: 0) {
                            if topFour.count > 2 {
                                GuestPhotoCell(photo: topFour[2], number: 3)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                            if topFour.count > 3 {
                                GuestPhotoCell(photo: topFour[3], number: 4)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
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
        GeometryReader { cell in
            ZStack {
                Color.black

                Image(nsImage: photo.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cell.size.width, height: cell.size.height)

                VStack {
                    HStack {
                        Text("\(number)")
                            .font(.system(size: 100, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.9), radius: 6, x: 3, y: 3)
                            .padding(24)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .border(Color.black, width: 3)
    }
}
