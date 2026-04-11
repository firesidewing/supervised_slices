/**
 * Countdown — live ETA display on the order tracking page.
 *
 * Reads `data-estimated-at` (Unix timestamp) and `data-status` from the element,
 * then ticks every 5 seconds to display remaining time + clock time.
 * Stops updating once the order is ready or completed.
 */
export const Countdown = {
  mounted() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 5000)

    // When LiveView pushes an `order_status_changed` event the status attribute
    // will have been updated by the server re-render, so we just tick again.
    this.handleEvent("order_status_changed", () => {
      this.tick()
    })
  },

  destroyed() {
    clearInterval(this.timer)
  },

  tick() {
    const estimatedAt = parseInt(this.el.dataset.estimatedAt, 10)
    const status = this.el.dataset.status

    if (["ready", "completed", "cancelled"].includes(status)) {
      clearInterval(this.timer)
      this.el.innerHTML = ""
      return
    }

    const now = Math.floor(Date.now() / 1000)
    const remaining = estimatedAt - now
    const readyTime = new Date(estimatedAt * 1000)
    const timeStr = readyTime.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })

    if (remaining <= 0) {
      this.el.innerHTML = `
        <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">Estimated wait</p>
        <p class="font-headline text-lg font-bold text-on-surface">Coming right up!</p>
        <p class="font-body text-xs text-on-surface-variant">Ready by ${timeStr}</p>
      `
    } else {
      const mins = Math.ceil(remaining / 60)
      this.el.innerHTML = `
        <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">Estimated wait</p>
        <p class="font-headline text-lg font-bold text-on-surface">~${mins} min</p>
        <p class="font-body text-xs text-on-surface-variant">Ready by ${timeStr}</p>
      `
    }
  }
}

/**
 * OrderNotifications — browser Notifications API opt-in on the tracking page.
 *
 * Shows an "Enable" button that requests permission, then listens for
 * `order_status_changed` events pushed from the server to fire notifications.
 */
export const OrderNotifications = {
  mounted() {
    const btn = document.getElementById("notification-btn")
    const publicKey = this.el.dataset.publicKey

    // If notifications aren't supported, just leave it hidden
    if (!("Notification" in window)) return

    // Only show the prompt if we haven't granted yet (and haven't explicitly denied)
    if (Notification.permission === "default") {
      this.el.classList.remove("hidden")
      this.el.classList.add("flex")
    }

    if (btn) {
      btn.addEventListener("click", () => {
        Notification.requestPermission().then((permission) => {
          if (permission === "granted") {
            this.el.classList.remove("flex")
            this.el.classList.add("hidden")
            this.showNotification("Notifications enabled!", "We'll let you know when your order is ready.")
            this.subscribeToPush(publicKey)
          }
        })
      })
    }

    this.handleEvent("order_status_changed", ({ message }) => {
      if (Notification.permission === "granted") {
        this.showNotification(message)
      }
    })
  },

  subscribeToPush(publicKey) {
    if (!("serviceWorker" in navigator)) return

    navigator.serviceWorker.ready.then((registration) => {
      registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: publicKey
      }).then((subscription) => {
        // subscription.toJSON() gives us the keys and endpoint
        const sub = subscription.toJSON()
        this.pushEvent("save_subscription", {
          endpoint: sub.endpoint,
          p256dh: sub.keys.p256dh,
          auth: sub.keys.auth
        })
      }).catch((error) => {
        console.error("Push subscription failed:", error)
      })
    })
  },

  showNotification(title, body) {
    const options = {
      body,
      icon: "/favicon.ico",
      badge: "/favicon.ico",
      vibrate: [200, 100, 200]
    }

    // On mobile, showNotification from the service worker is much more reliable
    // as it can often display even when the browser is backgrounded.
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.ready.then((registration) => {
        registration.showNotification(title, options)
      }).catch(() => {
        new Notification(title, options)
      })
    } else {
      new Notification(title, options)
    }
  }
}

/**
 * KitchenAlert — plays an audible chime and flashes the page title whenever
 * the server pushes a `new_order_alert` event (a new order has come in).
 *
 * Mount this hook on any persistent element in the kitchen dashboard layout.
 */
export const KitchenAlert = {
  mounted() {
    this.originalTitle = document.title
    this.flashInterval = null

    this.handleEvent("new_order_alert", () => {
      this.playChime()
      this.flashTitle()
    })
  },

  destroyed() {
    clearInterval(this.flashInterval)
    document.title = this.originalTitle
  },

  playChime() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      const notes = [523.25, 659.25, 783.99] // C5, E5, G5

      notes.forEach((freq, i) => {
        const osc = ctx.createOscillator()
        const gain = ctx.createGain()

        osc.connect(gain)
        gain.connect(ctx.destination)

        osc.type = "sine"
        osc.frequency.value = freq

        const startAt = ctx.currentTime + i * 0.15
        gain.gain.setValueAtTime(0, startAt)
        gain.gain.linearRampToValueAtTime(0.35, startAt + 0.02)
        gain.gain.exponentialRampToValueAtTime(0.001, startAt + 0.4)

        osc.start(startAt)
        osc.stop(startAt + 0.4)
      })
    } catch (_e) {
      // AudioContext unavailable — skip sound, visual flash still works
    }
  },

  flashTitle() {
    clearInterval(this.flashInterval)
    document.title = "🔔 New Order!"

    let count = 0
    this.flashInterval = setInterval(() => {
      count++
      document.title = count % 2 === 0 ? "🔔 New Order!" : this.originalTitle
      if (count >= 10) {
        clearInterval(this.flashInterval)
        document.title = this.originalTitle
      }
    }, 800)
  }
}

/**
 * GeoFenceMap — interactive Leaflet map for setting delivery area.
 */
export const GeoFenceMap = {
  mounted() {
    this.initMap()
  },

  updated() {
    this.updateRadius()
  },

  initMap() {
    const lat = parseFloat(this.el.dataset.lat) || 43.6532 // Toronto
    const lng = parseFloat(this.el.dataset.lng) || -79.3832
    const radiusInKm = parseFloat(this.el.dataset.radius) || 5.0

    this.map = L.map(this.el).setView([lat, lng], 13)

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)

    const icon = L.icon({
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41]
    })

    this.marker = L.marker([lat, lng], { draggable: true, icon }).addTo(this.map)

    this.circle = L.circle([lat, lng], {
      color: '#b90027',
      fillColor: '#b90027',
      fillOpacity: 0.1,
      radius: radiusInKm * 1000
    }).addTo(this.map)

    this.marker.on('dragend', (e) => {
      const { lat, lng } = e.target.getLatLng()
      this.circle.setLatLng([lat, lng])
      this.pushEventTo(this.el, 'update_geo_center', { lat, lng })
    })

    this.handleEvent("recenter_map", ({lat, lng}) => {
      this.marker.setLatLng([lat, lng])
      this.circle.setLatLng([lat, lng])
      this.map.setView([lat, lng], 13)
    })
  },

  updateRadius() {
    const radiusInKm = parseFloat(this.el.dataset.radius) || 5.0
    if (this.circle) {
      this.circle.setRadius(radiusInKm * 1000)
    }
  }
}
