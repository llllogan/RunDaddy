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
                    // This should be repalced with a swift chart donut (styled to look like a progress indicator) and represent the current progress percentage shown as the number figure
                    Circle()
                        .fill(.green)
                        .frame(maxHeight: 40)
                    VStack(alignment: .leading) {
                        // This text box should say "Machine Progress" if an item is being shown, "Location Progress" if an machine is being shown, and "Run Progress" if a location is being shown
                        Text("Machine Progress")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        // This should be the progress through the type the user is in the packing session, so 30% of the way through the run or 70% of the way through the machine and so on
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
                        // This should be the SKU name, or machine description, or location name
                        Text("Coke")
                            .font(.title.bold())
                        // This should be the SKU type, or machine code, or location name, or blank if location
                        Text("Bottle")
                            .font(.title3.bold())
                        // This should be the number of coils the SKU entry is being read out for or "1 Coil" if only one, or machine type description, or blank for location
                        Text("3 Coils")
                            .foregroundStyle(.secondary)
                            .font(.headline)
                        Spacer()
                        // If either a machine or location is being read out, these fields should be blank
                        Text("BR1 Fresh")
                            .font(.headline)
                        Text("Aldi Brendale")
                            .font(.headline)
                    }
                    Spacer()
                    // This is the number of items needed to be packed. THis will be blank if machine or location
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
                    // This should be a comma separated list of the chocolate box number acossiated to this machine for this run
                    Text("3, 4, 58, 3")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                HStack(spacing: 4) {
                    Button {
                        
                    } label: {
                        HStack {
                            // This should make the add chocolate box sheet appear
                            Label("Chocolate Box", systemImage: "plus.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        
                    } label: {
                        HStack {
                            // This should add this SKU to the cheese tub
                            // This is the state of the SKU not being in the cheese tub (is cheese and crackers)
                            // THere should be another state for is in the cheese tub, and pressing this button should toggle that field
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
                    // Ignore this functionality for now
                    Button("Pause", systemImage: "pause.fill") {
                        
                    }
                    // This should stop the packing session
                    Button("Stop", systemImage: "stop.fill") {
                        
                    }
                    .tint(.red)
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    // This should skip the current pick entry
                    Button("Skip") {
                        
                    }
                    Spacer()
                    // This should go back to the previous instruction
                    Button("Back", systemImage: "backward.fill") {
                        
                    }
                    // This should repeat the current instruction
                    Button("Repeat", systemImage: "repeat") {
                        
                    }
                    // This should mark the current pick entry as packed and then move onto the next insturction
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
//                            .font(.headline)
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
