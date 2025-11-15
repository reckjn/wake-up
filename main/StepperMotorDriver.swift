private let MICROSECONDS_PER_MINUTE = UInt32(60_000_000)

// StepperMotorDriver is built for a T2208 motor driver.
struct StepperMotorDriver {
    let motor: Motor
    let pins: Pins
    let microsteps: Int
    let stepsPerRevolution: Int
    var speed: RPM {
        // 60 RPM = 1 revolution per second
        didSet {
            ensureSpeedIsWithinMaxSpeed()
        }
    }

    init(motor: Motor, pins: Pins, microsteps: Int, speed: RPM = 60) {
        self.motor = motor 
        self.pins = pins
        self.microsteps = microsteps
        self.stepsPerRevolution = motor.stepsPerRevolution * microsteps
        self.speed = speed

        ensureSpeedIsWithinMaxSpeed()
        initializePins()
    }

    private mutating func ensureSpeedIsWithinMaxSpeed() {
        if speed > motor.maxSpeed {
            print("WARNING! Max speed is \(motor.maxSpeed) RPM, desired speed is \(speed) RPM which is too high. Setting speed to \(motor.maxSpeed) RPM")
            speed = motor.maxSpeed
        }
    }

    private func initializePins() {
        gpio_reset_pin(pins.direction)
        gpio_set_direction(pins.direction, GPIO_MODE_OUTPUT)
        gpio_reset_pin(pins.step)
        gpio_set_direction(pins.step, GPIO_MODE_OUTPUT)
        gpio_reset_pin(pins.enable)
        gpio_set_direction(pins.enable, GPIO_MODE_OUTPUT)
        gpio_set_level(pins.step, 0)
        gpio_set_level(pins.direction, Direction.clockwise.rawValue)
        gpio_set_level(pins.enable, 1)  // Disable motor by default (active LOW)
    }

    func turn(degrees: Double) {
        let direction = degrees >= 0 ? Direction.clockwise : Direction.counterclockwise
        setDirection(direction: direction)

        let steps = Int(abs(degrees) * Double(stepsPerRevolution) / 360.0)
        let delayMicroSeconds = MICROSECONDS_PER_MINUTE / UInt32(speed * stepsPerRevolution)

        for _ in 0..<steps {
            gpio_set_level(pins.step, 1)
            esp_rom_delay_us(delayMicroSeconds)
            gpio_set_level(pins.step, 0)
        }
    }

    func setDirection(direction: Direction) {
        gpio_set_level(pins.direction, direction.rawValue)
    }

    func enable() {
        gpio_set_level(pins.enable, 0)
    }

    func disable() {
        gpio_set_level(pins.enable, 1)
    }

    mutating func setSpeed(speed: RPM) {
        self.speed = speed
    }
}

typealias RPM = Int

extension StepperMotorDriver {
    struct Pins {
        let enable: gpio_num_t
        let step: gpio_num_t
        let direction: gpio_num_t
    }
}

extension StepperMotorDriver {
    enum Direction: UInt32 {
        case clockwise = 1
        case counterclockwise = 0
    }
}
