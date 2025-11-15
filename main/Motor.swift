struct Motor {
    let maxSpeed: RPM
    let stepsPerRevolution: Int
}

let NEMA_17 = Motor(maxSpeed: 200, stepsPerRevolution: 200)