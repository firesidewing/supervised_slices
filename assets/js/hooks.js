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

    // Hide the whole prompt if notifications aren't supported or already granted
    if (!("Notification" in window)) {
      this.el.style.display = "none"
      return
    }

    if (Notification.permission === "granted") {
      this.el.style.display = "none"
    }

    if (btn) {
      btn.addEventListener("click", () => {
        Notification.requestPermission().then((permission) => {
          if (permission === "granted") {
            this.el.style.display = "none"
            new Notification("Notifications enabled!", {
              body: "We'll let you know when your order is ready.",
            })
          }
        })
      })
    }

    this.handleEvent("order_status_changed", ({ status, message }) => {
      if (Notification.permission === "granted") {
        new Notification(message)
      }
    })
  }
}
