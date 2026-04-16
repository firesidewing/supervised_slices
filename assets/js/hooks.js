import { driver } from "driver.js"

/**
 * TourGuide — spotlight-style onboarding tour for the admin Kitchen Command dashboard.
 *
 * Auto-starts on first visit (data-tour-autostart="true") and can be triggered
 * at any time by dispatching a "start-tour" event on window.
 * Pushes "tour_completed" to the server when the tour is dismissed or finished.
 */
export const TourGuide = {
  mounted() {
    this._tour = driver({
      showProgress: true,
      showButtons: ["next", "previous", "close"],
      nextBtnText: "Next →",
      prevBtnText: "← Back",
      doneBtnText: "Done",
      progressText: "{{current}} of {{total}}",
      popoverClass: "kitchen-tour-popover",
      onDestroyed: () => {
        this.pushEvent("tour_completed", {})
      },
      steps: [
        {
          element: "[data-tour='nav']",
          popover: {
            title: "Welcome to Kitchen Command",
            description: "This is your live dashboard for managing orders, monitoring guests, and configuring your store. Let's walk through the key sections."
          }
        },
        {
          element: "[data-tour='orders-link']",
          popover: {
            title: "Order Atelier",
            description: "The heart of the kitchen. New orders appear here in real time as customers check out. Advance each order through Pending → Preparing → Ready → Completed.",
            side: "bottom",
            align: "start"
          }
        },
        {
          element: "[data-tour='baskets-link']",
          popover: {
            title: "Basket Monitor",
            description: "See what guests are adding to their carts before they check out. Useful for anticipating upcoming orders.",
            side: "bottom",
            align: "start"
          }
        },
        {
          element: "[data-tour='menu-link']",
          popover: {
            title: "Menu Atelier",
            description: "Build and edit your menu — add categories, items, and descriptions. Changes go live instantly.",
            side: "bottom",
            align: "start"
          }
        },
        {
          element: "[data-tour='settings-link']",
          popover: {
            title: "System Settings",
            description: "Configure your store hours, delivery zones, team members, branding, and integrations.",
            side: "bottom",
            align: "start"
          }
        },
        {
          element: "[data-tour='metrics']",
          popover: {
            title: "Live Metrics",
            description: "Active ticket count and average fire time update in real time so you always know the kitchen's current load.",
            side: "top"
          }
        },
        {
          element: "[data-tour='phone-order']",
          popover: {
            title: "Phone Orders",
            description: "Taking an order over the phone? Use this to build and submit a manual order directly into the queue.",
            side: "top"
          }
        },
        {
          element: "[data-tour='visitor-count']",
          popover: {
            title: "Live Visitors",
            description: "Shows how many guests are currently browsing your menu — a helpful signal for anticipating order volume.",
            side: "bottom",
            align: "end"
          }
        }
      ]
    })

    if (this.el.dataset.tourAutostart === "true") {
      // Small delay to let the page settle before the first highlight
      setTimeout(() => this._tour.drive(), 400)
    }

    window.addEventListener("start-tour", this._onStartTour = () => this._tour.drive())
  },

  destroyed() {
    window.removeEventListener("start-tour", this._onStartTour)
  }
}

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
            if (window.posthog) posthog.capture("notification_permission_granted")
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
        if (window.posthog) posthog.captureException(error, { extra: { context: "push_subscription" } })
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
      const AudioContext = window.AudioContext || window.webkitAudioContext
      if (!AudioContext) return
      const ctx = new AudioContext()

      // Generate a short buffer of white noise
      const bufferSize = ctx.sampleRate * 0.1
      const noiseBuffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate)
      const output = noiseBuffer.getChannelData(0)
      for (let i = 0; i < bufferSize; i++) {
        output[i] = Math.random() * 2 - 1
      }

      // Filter the noise to sound more like a mechanical printer pin strike
      const filter = ctx.createBiquadFilter()
      filter.type = "bandpass"
      filter.frequency.value = 3200
      filter.Q.value = 1.0
      filter.connect(ctx.destination)

      // Dot matrix "chit printing" sound: rhythmic bursts of noise
      const bursts = [
        {time: 0.00, duration: 0.03, volume: 0.15},
        {time: 0.06, duration: 0.03, volume: 0.15},
        {time: 0.12, duration: 0.03, volume: 0.15},
        {time: 0.18, duration: 0.04, volume: 0.20},
        {time: 0.28, duration: 0.03, volume: 0.15},
        {time: 0.34, duration: 0.03, volume: 0.15},
        {time: 0.40, duration: 0.03, volume: 0.15},
        {time: 0.46, duration: 0.04, volume: 0.20},
        {time: 0.60, duration: 0.05, volume: 0.25} // Final "paper cut" sound
      ]

      bursts.forEach(b => {
        const source = ctx.createBufferSource()
        source.buffer = noiseBuffer
        const gain = ctx.createGain()
        source.connect(gain)
        gain.connect(filter)

        const startAt = ctx.currentTime + b.time
        gain.gain.setValueAtTime(0, startAt)
        gain.gain.linearRampToValueAtTime(b.volume, startAt + 0.005)
        gain.gain.linearRampToValueAtTime(0, startAt + b.duration)

        source.start(startAt)
        source.stop(startAt + b.duration)
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
 * PostHogIdentify — syncs the current user/org identity to PostHog on mount
 * and after every LiveView patch (org navigations, login/logout).
 */
export const PostHogIdentify = {
  mounted() { this._identify() },
  updated() { this._identify() },
  _identify() {
    if (!window.posthog) return
    const { userId, userEmail, superadmin, orgId, orgName, orgPlan } = this.el.dataset
    if (superadmin === "true") return
    if (userId) {
      posthog.identify(userId, { email: userEmail })
    } else {
      posthog.reset()
    }
    if (orgId) {
      posthog.group("organization", orgId, { name: orgName, plan: orgPlan })
    }
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
