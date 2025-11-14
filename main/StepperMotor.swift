//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

// Helper object to control a 28BYJ-48 stepper motor with ULN2003 driver.
// Provides low-level APIs for stepping the motor forward/backward with speed control.
final class StepperMotor {

  // Configuration for stepper motor GPIO pins
  struct Config {
    let in1Pin: gpio_num_t
    let in2Pin: gpio_num_t
    let in3Pin: gpio_num_t
    let in4Pin: gpio_num_t
    let stepsPerRevolution: Int

    init(
      in1Pin: gpio_num_t = GPIO_NUM_18,
      in2Pin: gpio_num_t = GPIO_NUM_19,
      in3Pin: gpio_num_t = GPIO_NUM_20,
      in4Pin: gpio_num_t = GPIO_NUM_21,
      stepsPerRevolution: Int = 2048  // 28BYJ-48 default (64:1 gear ratio * 32 steps)
    ) {
      self.in1Pin = in1Pin
      self.in2Pin = in2Pin
      self.in3Pin = in3Pin
      self.in4Pin = in4Pin
      self.stepsPerRevolution = stepsPerRevolution
    }
  }

  // Half-step sequence for smooth operation (8 phases)
  private let stepSequence: [[UInt32]] = [
    [1, 0, 0, 0],
    [1, 1, 0, 0],
    [0, 1, 0, 0],
    [0, 1, 1, 0],
    [0, 0, 1, 0],
    [0, 0, 1, 1],
    [0, 0, 0, 1],
    [1, 0, 0, 1]
  ]

  private let config: Config
  private var currentStep: Int = 0

  // Whether the motor coils are powered (enables holding torque)
  var isPowered: Bool = true {
    didSet {
      if isPowered {
        // Re-energize at current position
        setStep(currentStep)
      } else {
        // Power down all coils
        powerDown()
      }
    }
  }

  // Speed control: delay in microseconds between steps (1000-10000μs typical)
  // Lower values = faster rotation, but too low will cause missed steps
  var speed: UInt32 = 2000 {  // 2000μs = 2ms per step
    didSet {
      speed = max(1500, min(20000, speed))  // Clamp to safe range (1-20ms)
    }
  }

  init(config: Config = Config()) {
    self.config = config

    // Configure GPIO pins as outputs
    var ioConfig = gpio_config_t()
    ioConfig.pin_bit_mask = (1 << config.in1Pin.rawValue) |
                            (1 << config.in2Pin.rawValue) |
                            (1 << config.in3Pin.rawValue) |
                            (1 << config.in4Pin.rawValue)
    ioConfig.mode = GPIO_MODE_OUTPUT
    ioConfig.pull_up_en = GPIO_PULLUP_DISABLE
    ioConfig.pull_down_en = GPIO_PULLDOWN_DISABLE
    ioConfig.intr_type = GPIO_INTR_DISABLE

    let result = gpio_config(&ioConfig)
    guard result == ESP_OK else {
      fatalError("Failed to configure GPIO pins for stepper motor")
    }

    // Initialize all pins to LOW
    gpio_set_level(config.in1Pin, 0)
    gpio_set_level(config.in2Pin, 0)
    gpio_set_level(config.in3Pin, 0)
    gpio_set_level(config.in4Pin, 0)
  }

  // Apply a specific step pattern to the GPIO pins
  private func setStep(_ step: Int) {
    let pattern = stepSequence[step]
    gpio_set_level(config.in1Pin, pattern[0])
    gpio_set_level(config.in2Pin, pattern[1])
    gpio_set_level(config.in3Pin, pattern[2])
    gpio_set_level(config.in4Pin, pattern[3])
  }

  // Step with S-curve acceleration for smooth, quiet operation
  private func stepWithSCurveAcceleration(steps: Int, forward: Bool) {
    let accelerationSteps = min(steps / 3, 200)  // Use 1/3 for acceleration
    let startSpeed = UInt32(4000)  // Start slow (4ms)
    let targetSpeed = speed         // Use configured target speed

    for i in 0..<steps {
      var speedMultiplier: Float = 1.0

      // S-curve acceleration phase
      if i < accelerationSteps {
        let progress = Float(i) / Float(accelerationSteps)
        // Smooth S-curve formula
        speedMultiplier = Float(0.5 * (1 - cos(Double(Float.pi * progress))))
      }
      // S-curve deceleration phase
      else if i > (steps - accelerationSteps) {
        let progress = Float(steps - i) / Float(accelerationSteps)
        speedMultiplier = Float(0.5 * (1 - cos(Double(Float.pi * progress))))
      }

      let currentSpeed = targetSpeed + UInt32(Float(startSpeed - targetSpeed) * (1 - speedMultiplier))

      // Perform the step
      if forward {
        currentStep = (currentStep + 1) % 8
      } else {
        currentStep = (currentStep - 1 + 8) % 8
      }
      setStep(currentStep)
      esp_rom_delay_us(currentSpeed)
    }
  }

  // Step forward by the specified number of steps
  func stepForward(steps: Int) {
    stepWithSCurveAcceleration(steps: steps, forward: true)
  }

  // Step backward by the specified number of steps
  func stepBackward(steps: Int) {
    stepWithSCurveAcceleration(steps: steps, forward: false)
  }

  // Power down all coils to save power and reduce heat
  func powerDown() {
    gpio_set_level(config.in1Pin, 0)
    gpio_set_level(config.in2Pin, 0)
    gpio_set_level(config.in3Pin, 0)
    gpio_set_level(config.in4Pin, 0)
  }

  // Re-energize the motor at the current position
  func powerUp() {
    setStep(currentStep)
  }

  // Rotate by a specific number of degrees
  // Positive values rotate forward, negative values rotate backward
  func rotate(degrees: Int) {
    let steps = (config.stepsPerRevolution * abs(degrees)) / 360
    if degrees > 0 {
      stepForward(steps: steps)
    } else {
      stepBackward(steps: steps)
    }
  }
}
