//
//  VPWHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 17.06.25.
//


import SwiftUI

struct VPWHelpView: View {
    @State private var showDetails: Bool = false
    
    let fields: [(String, String)] = [
        ("x.x", "Speed in knots (\"-\" = downwind)"),
        ("N", "Knots unit indicator"),
        ("x.x", "Speed in meters/second (\"-\" = downwind)"),
        ("M", "Meters/second unit indicator")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("VPW – Speed Measured Parallel to Wind")
                    .font(.title3.bold())
                
                Text("The component of the vessel’s velocity vector parallel to the direction of the true wind. Sometimes called \"speed made good to windward\" or \"velocity made good to windward\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("$--VPW,x.x,N,x.x,M*hh<CR><LF>")
                    .font(.system(.body, design: .monospaced).bold())
                
                // Expandable field breakdown
                Button(action: {
                    withAnimation {
                        showDetails.toggle()
                    }
                }) {
                    HStack {
                        Text("Field Breakdown")
                            .foregroundColor(.accentColor)
                            .font(.body.bold())
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                
                if showDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(fields.indices, id: \.self) { index in
                            let item = fields[index]
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.0)
                                    .frame(width: 50, alignment: .trailing)
                                    .fontWeight(.semibold)
                                Text(item.1)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.leading, 8)
                    }
                    
                }
                Divider()
                    .padding(.vertical)
                
                Text("Example:")
                    .font(.subheadline.bold())
                
                Text("$WIVPW,2.3,N,1.2,M*hh")
                    .font(.system(.body, design: .monospaced))
                
                Text("↳ Speed parallel to wind: 2.3 knots, 1.2 m/s (both values positive = upwind)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
        }
    }
}

#Preview {
    VPWHelpView()
        .frame(width: 500, height: 400)
}
