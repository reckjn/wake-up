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

@_cdecl("app_main")
func main() {

  let led = LED()

  // (1) Create a Matter root node
  let rootNode = Matter.Node()
  rootNode.identifyHandler = {
    print("identify")
  }

  // (2) Create a "light" endpoint
  let lightEndpoint = Matter.ExtendedColorLight(node: rootNode)
  lightEndpoint.eventHandler = { event in
    print("lightEndpoint.eventHandler:")
    print(event.attribute)
    print(event.value)

    switch event.attribute {
    case .onOff:
      led.enabled = (event.value == 1)

    case .levelControl:
      led.brightness = Int(Float(event.value) / 255.0 * 100.0)

    case .colorControl(.currentHue):
      let newHue = Int(Float(event.value) / 255.0 * 360.0)
      led.color = .hueSaturation(newHue, led.color.saturation)

    case .colorControl(.currentSaturation):
      let newSaturation = Int(Float(event.value) / 255.0 * 100.0)
      led.color = .hueSaturation(led.color.hue, newSaturation)

    case .colorControl(.colorTemperatureMireds):
      let kelvins = 1_000_000 / event.value
      led.color = .temperature(kelvins)

    default:
      break
    }
  }

  // (3) Add the endpoint to the node
  rootNode.addEndpoint(lightEndpoint)

  // (4) Provide the node to a Matter application and start it
  let app = Matter.Application()
  app.rootNode = rootNode
  app.start()

  // Initialize time synchronization
  let timer = Timer()

  let pins = StepperMotorDriver.Pins(enable: GPIO_NUM_4, step: GPIO_NUM_5, direction: GPIO_NUM_6)
  let motorDriver = StepperMotorDriver(motor: NEMA_17, pins: pins, microsteps: 8)
  motorDriver.enable()

  while true {
    timer.updateCurrentTime()
    if let timerCurrentTime = timer.currentTime {
      print("Current Time: \(timerCurrentTime.toString())")

      if timerCurrentTime.second % 5 == 0 {
        motorDriver.turn(degrees: -720) {
          print("Motor turned completed")
        }
      }
      if timerCurrentTime.second % 5 == 1 {
        motorDriver.stop()
      }

      sleep(1)
    }
  }
}
