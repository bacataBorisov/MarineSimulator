# 🧭 MarineSimulator

A **macOS** app (SwiftUI + MapKit) for **simulating and visualizing marine navigation data** — heading, wind, speed, depth, and GPS — without needing onboard instruments. Ideal for prototyping, testing, and demos of NMEA-style workflows.

---

## ✨ Highlights

- **Real-time simulation** of vessel data (GPS, Compass, Wind, Speed/Depth)
- **Interactive MapKit view** with a custom boat marker and smooth heading animation
- **Manual pan/zoom** with a one-tap **“Center on Boat”** control (no forced follow)
- **Compact control panels** (left) for quick tuning via sliders
- **Inspector panel** (right) for live readouts and instrument widgets
- **Optional UDP broadcast** of NMEA-like sentences for external consumers
- **SwiftUI-first** architecture; clean, extendable components

> **Target:** macOS 14+ (Sonoma) or newer, Xcode 15+ recommended.

---

## 🖼️ Screenshots

> Place your images in `assets/media/` and keep the filenames below, or adjust the paths.

### Dashboard (Light & Dark)
| Light | Dark |
|---|---|
| ![Dashboard Light](assets/media/dashboard_light.png) | ![Dashboard Dark](assets/media/dashboard_dark.png) |

### Map View
![Map View](assets/media/map_preview.png)

### Console
![Console](assets/media/console_view.png)

---

## 🎥 Demo Videos (optional)

- 📺 **Quick Overview:** https://youtu.be/your_demo_video_here  
- 🛠️ **Longer Walkthrough:** https://youtu.be/your_overview_video_here

---

## 🚀 Getting Started

### 1) Clone
```bash
git clone https://github.com/bacataBorisov/MarineSimulator.git
cd MarineSimulator

---

### 2) Open & Run

1. Open the project in **Xcode**, select **My Mac** as the run destination.  
2. Build & Run. The app launches with:

   - 🗺️ A large **Map** in the center  
   - 🎛️ **Top control bar** with quick actions (e.g., *Center on Boat*)  
   - ⚙️ **Left panel** with sliders (*Wind, Heading, Hydro, GPS*)  
   - 📊 **Right panel** with instruments/readouts  
   - 💬 **Bottom console** (optional) for live sentence preview  

---

### 3) Simulate

- Use the **left sliders** to tweak *TWD/TWS, Heading, Speed/Depth, COG/SOG*.  
- Watch the **boat marker rotate and move**.  
- Click **Center** to re-focus the camera on your current position.  

---

## ⚙️ Feature Details

### 🗺️ Map & Boat Marker
- Built with **Apple MapKit** (fast and smooth base map).  
- Boat marker uses an **SF Symbol**, tinted **orange/yellow**.  
- Heading changes **animate smoothly**; the camera only recenters when you tap **Center**.  

### 🎚️ Controls & Panels
- **Left Controls:** sliders for *Wind (TWD/TWS)*, *Hydro (Speed/Depth/Temp)*, *Heading*, and *GPS*.  
- **Right Inspector:** compact instrument cards (*anemometer, compass, key metrics*).  
- **Top Bar:** visibility toggles for panels and a *Center on Boat* button.  

### 🌐 Simulation & Output
- Internal timer produces **continuous updates**.  
- Supports **NMEA-style encoding** of common sentences (*MWV, MWD, VHW, DPT, RMC*).  
- Optional **UDP broadcasting** for testing external apps (configurable port and cadence).  

---

## 🧪 Tips

- For testing map controls, **pan/zoom freely** — the app does **not auto-follow** the boat.  
- Use **Center** when you want to snap the camera back to the vessel.  
- If you see **heavy logging** during development, reduce verbosity in Xcode’s scheme settings.  

---

## 🗺️ Future Features

- 🌊 Seamarks overlay (**OpenSeaMap**) as an optional layer  
- 🧭 Bathymetry with depth contours/labels (**EMODnet/ENC integration**)  
- ⚡ Instrument failure or latency simulation  
- 🌬️ Preset scenarios (*Calm, Breezy, Storm*)  
- 🔌 NMEA 2000 / CAN bridging  
- 💾 Data recording & replay (CSV export)  
- ⚙️ Custom units and smoothing/filters (e.g., *simple Kalman filter*)  

---

## 📄 License

Released under the **MIT License**.  
See the [LICENSE](LICENSE) file for details.  

---

## 👤 Author

**Vasil Borisov**  
Marine Electronics Enthusiast • Software Developer  

📧 **Email:** [bacata.borisov@gmail.com](mailto:bacata.borisov@gmail.com)  
🐙 **GitHub:** [github.com/bacataBorisov](https://github.com/bacataBorisov)  
