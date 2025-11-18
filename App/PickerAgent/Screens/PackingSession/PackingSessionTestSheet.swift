//
//  PackingSessionTestSheet.swift
//  PickerAgent
//
//  Created by Logan Janssen | Codify on 18/11/2025.
//

import SwiftUI

struct PackingSessionTestSheet: View {
    
    var body: some View {
        
        NavigationStack {
            
            // Layout for vertical iPhone only
            
            VStack {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(maxHeight: 40)
                    VStack(alignment: .leading) {
                        Text("Machine Progress")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Text("30%")
                            .font(.title3.bold())
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("Coke")
                            .font(.title.bold())
                        Text("Bottle")
                            .font(.title3.bold())
                        Text("3 Coils")
                            .foregroundStyle(.secondary)
                            .font(.headline)
                        Spacer()
                        Text("BR1 Fresh")
                            .font(.headline)
                        Text("Aldi Brendale")
                            .font(.headline)
                    }
                    Spacer()
                    Text("5")
                        .font(.init(.custom("PackCounter", size: 100, relativeTo: .largeTitle)))
                        .fontDesign(.rounded)
                        .fontWeight(.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choclate Box Numbers")
                        .foregroundStyle(.secondary)
                        .font(.caption2.bold())
                        .padding(.leading, 8)
                    Text("3, 4, 58, 3")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                HStack(spacing: 4) {
                    Button {
                        
                    } label: {
                        HStack {
                            Label("Chocolate Box", systemImage: "plus.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        
                    } label: {
                        HStack {
                            Label("Cheese Tub", systemImage: "plus.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(.yellow)
                    .buttonStyle(.borderedProminent)
                }
            }
            .ignoresSafeArea()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Pause", systemImage: "pause.fill") {
                        
                    }
                    Button("Stop", systemImage: "stop.fill") {
                        
                    }
                    .tint(.red)
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Skip") {
                        
                    }
                    Spacer()
                    Button("Back", systemImage: "backward.fill") {
                        
                    }
                    Button("Repeat", systemImage: "repeat") {
                        
                    }
                    Button("Next", systemImage: "forward.fill") {
                        
                    }
                }
            }
            
            // Below this is the layout for iPads and when iPhone is horozontal
            
//            HStack(alignment: .top, spacing: 8) {
//                VStack {
//                    Button {
//                        
//                    } label: {
//                        HStack {
//                            Label("Chocolate Box", systemImage: "plus.circle.fill")
//                            Spacer()
//                        }
//                        .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.borderedProminent)
//                    
//                    
//                    Button {
//                        
//                    } label: {
//                        HStack {
//                            Label("Cheese Tub", systemImage: "plus.circle.fill")
//                            Spacer()
//                        }
//                        .frame(maxWidth: .infinity)
//                    }
//                    .tint(.yellow)
//                    .buttonStyle(.borderedProminent)
//                    
//                    VStack(alignment: .leading, spacing: 2) {
//                        Text("Choclate Box Numbers")
//                            .foregroundStyle(.secondary)
//                            .font(.caption2.bold())
//                            .padding(.leading, 8)
//                        Text("3, 4, 58, 3")
//                            .frame(maxWidth: .infinity, maxHeight: .infinity)
//                            .padding()
//                            .background(Color(.secondarySystemGroupedBackground))
//                            .clipShape(RoundedRectangle(cornerRadius: 16))
//                    }
//                    .padding(.top, 6)
//                }
//                
//                HStack(alignment: .top) {
//                    VStack(alignment: .leading) {
//                        Text("Coke")
//                            .font(.title.bold())
//                        Text("Bottle")
//                            .font(.title3.bold())
//                        Text("3 Coils")
//                            .foregroundStyle(.secondary)
//                            .font(.headline)
//                        Spacer()
//                        Text("BR1 Fresh")
//                            .font(.headline)
//                        Text("Aldi Brendale")
//                            .font(.headline)
//                    }
//                    Spacer()
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .padding()
//                .background(Color(.secondarySystemGroupedBackground))
//                .clipShape(RoundedRectangle(cornerRadius: 16))
//                
//                VStack {
//                    Text("5")
//                        .font(.init(.custom("PackCounter", size: 100, relativeTo: .largeTitle)))
//                        .fontDesign(.rounded)
//                        .fontWeight(.black)
//                        .frame(maxWidth: .infinity)
//                        .padding()
//                        .background(Color(.secondarySystemGroupedBackground))
//                        .clipShape(RoundedRectangle(cornerRadius: 16))
//                    
//                    HStack {
//                        Circle()
//                            .fill(.green)
//                            .frame(maxHeight: 40)
//                        VStack(alignment: .leading) {
//                            Text("Machine Progress")
//                                .foregroundStyle(.secondary)
//                                .font(.callout)
//                            Text("30%")
//                                .font(.title3.bold())
//                        }
//                        Spacer()
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(Color(.systemFill))
//                    .clipShape(RoundedRectangle(cornerRadius: 16))
//                }
//            }
//            .ignoresSafeArea()
//            .padding(.horizontal, 5)
//            .padding(.vertical, 1)
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//            .background(Color(.systemGroupedBackground))
//            .toolbar {
//                ToolbarItemGroup(placement: .topBarTrailing) {
//                    Button("Pause", systemImage: "pause.fill") {
//                        
//                    }
//                    Button("Stop", systemImage: "stop.fill") {
//                        
//                    }
//                    .tint(.red)
//                }
//                
//                ToolbarItemGroup(placement: .bottomBar) {
//                    Button("Skip") {
//                        
//                    }
//                    Spacer()
//                    Button("Back", systemImage: "backward.fill") {
//                        
//                    }
//                    Button("Repeat", systemImage: "repeat") {
//                        
//                    }
//                    Button("Next", systemImage: "forward.fill") {
//                        
//                    }
//                }
//            }
            
            
        }
    }
}


#Preview {
    PackingSessionTestSheet()
}
