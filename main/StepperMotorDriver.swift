private let MICROSECONDS_PER_MINUTE = UInt64(60_000_000)

// StepperMotorDriver is built for a T2208 motor driver.
final class StepperMotorDriver {
    private let motor: Motor
    private let pins: Pins
    private let microsteps: Int
    private let stepsPerRevolution: Int
    private(set) var speed: RPM {
        // 60 RPM = 1 revolution per second
        didSet {
            ensureSpeedIsWithinMaxSpeed()
        }
    }

    private var remainingStepsOfCurrentTurn: Int = 0
    private var turnCompletionHandler: (() -> Void)? = nil
    private var timerConfig: esp_timer_create_args_t
    private var timerHandle: esp_timer_handle_t?

    init(motor: Motor, pins: Pins, microsteps: Int, speed: RPM = 60) {
        self.motor = motor
        self.pins = pins
        self.microsteps = microsteps
        self.stepsPerRevolution = motor.stepsPerRevolution * microsteps
        self.speed = speed

        self.timerConfig = esp_timer_create_args_t()
        timerConfig.callback = { driverPointer in
            guard let driverPointer else { return }
            let driver = Unmanaged<StepperMotorDriver>.fromOpaque(driverPointer).takeUnretainedValue()
            driver.timerCallback()
        }
        timerConfig.arg = Unmanaged.passUnretained(self).toOpaque()
        timerConfig.dispatch_method = ESP_TIMER_TASK
        timerConfig.name = "stepper_timer_turn".withCString { $0 }

        ensureSpeedIsWithinMaxSpeed()
        initializePins()

        // Leak the object to ensure it stays alive for C callbacks
        _ = Unmanaged.passRetained(self)
    }

    private func ensureSpeedIsWithinMaxSpeed() {
        if speed > motor.maxSpeed {
            print(
                "WARNING! Max speed is \(motor.maxSpeed) RPM, desired speed is \(speed) RPM which is too high. Setting speed to \(motor.maxSpeed) RPM"
            )
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

    // Non-blocking
    func turn(degrees: Double, completion: (() -> Void)? = nil) {
        stop()

        let direction = degrees >= 0 ? Direction.clockwise : Direction.counterclockwise
        setDirection(direction: direction)

        let steps = Int(abs(degrees) * Double(stepsPerRevolution) / 360.0)
        let stepIntervalMicroseconds = MICROSECONDS_PER_MINUTE / UInt64(speed * stepsPerRevolution)

        self.remainingStepsOfCurrentTurn = steps
        self.turnCompletionHandler = completion

        var createdTimer: esp_timer_handle_t?
        let timerCreationResult = esp_timer_create(&timerConfig, &createdTimer)
        guard timerCreationResult == ESP_OK, let createdTimer else {
            print("Failed to create timer: \(timerCreationResult)")
            completion?()
            return
        }

        self.timerHandle = createdTimer
        esp_timer_start_periodic(createdTimer, UInt64(stepIntervalMicroseconds))
    }

    private func timerCallback() {
        guard remainingStepsOfCurrentTurn > 0 else {
            stop()
            turnCompletionHandler?()
            turnCompletionHandler = nil
            return
        }

        gpio_set_level(pins.step, 1)
        gpio_set_level(pins.step, 0)
        remainingStepsOfCurrentTurn -= 1
    }

    func stop() {
        if let handle = timerHandle {
            esp_timer_stop(handle)
            esp_timer_delete(handle)
            timerHandle = nil
        }
        gpio_set_level(pins.step, 0)
        remainingStepsOfCurrentTurn = 0
    }

    func enable() {
        stop()
        gpio_set_level(pins.enable, 0)
    }

    func disable() {
        stop()
        gpio_set_level(pins.enable, 1)
    }

    func setSpeed(speed: RPM) {
        self.speed = speed
    }

    private func setDirection(direction: Direction) {
        gpio_set_level(pins.direction, direction.rawValue)
    }

    deinit {
        stop()
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
