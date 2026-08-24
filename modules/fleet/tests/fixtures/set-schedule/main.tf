output "fleets" {
  value = {
    default = {
      runner = "small-x64"
      schedule = toset([
        { name = "z-fallback", hot = 1, stopped = 0 },
        { name = "a-specific", hot = 0, stopped = 1 },
      ])
    }
  }
}
