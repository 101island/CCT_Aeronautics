import math

import matplotlib.pyplot as plt


class BezierPoint:
    def __init__(self, altitude: float, value: float, slope: float) -> None:
        self.altitude = altitude
        self.value = value
        self.slope = slope


class BezierResourceFunction:
    def __init__(self) -> None:
        self.points: list[BezierPoint] = []

    def add_point(self, point: BezierPoint) -> None:
        self.points.append(point)

    def evaluate_function(self, position: float) -> float:
        if not self.points:
            return 1.0
        if len(self.points) == 1:
            return self.points[0].value

        index = -1
        for point in self.points:
            if position < point.altitude:
                break
            index += 1

        if index == -1:
            return self.points[0].value
        if index >= len(self.points) - 1:
            return self.points[-1].value

        point1 = self.points[index]
        point2 = self.points[index + 1]

        relative_x = point2.altitude - point1.altitude
        relative_y = point2.value - point1.value
        slope1 = point1.slope
        slope2 = point2.slope
        t = (position - point1.altitude) / relative_x

        cubic_factor = (slope1 + slope2) * relative_x - 2.0 * relative_y
        quadratic_factor = 3.0 * relative_y - (2.0 * slope1 + slope2) * relative_x
        linear_factor = relative_x * slope1

        return max(
            ((cubic_factor * t + quadratic_factor) * t + linear_factor) * t
            + point1.value,
            0.0,
        )


def create_default_pressure_curve(
    sea_level: float, min_y: float, logical_height: float
) -> BezierResourceFunction:
    current_altitude = min_y
    max_altitude = current_altitude + logical_height

    base_slope = -0.004
    max_pressure = 1.5
    max_step = 200.0
    smoothing_altitude = max_altitude - 40.0

    current_altitude = max(
        current_altitude, math.log(max_pressure) / base_slope + sea_level
    )

    pressure_function = BezierResourceFunction()

    while True:
        current_pressure = math.exp(base_slope * (current_altitude - sea_level))
        current_slope = current_pressure * base_slope
        pressure_function.add_point(
            BezierPoint(current_altitude, current_pressure, current_slope)
        )

        if current_altitude < sea_level and current_altitude + max_step >= sea_level:
            current_altitude = sea_level
        elif (
            current_altitude < smoothing_altitude
            and current_altitude + max_step >= smoothing_altitude
        ):
            current_altitude = smoothing_altitude
        elif current_altitude >= smoothing_altitude:
            break
        else:
            current_altitude += max_step

    smoothing_pressure = pressure_function.points[-1].value
    final_slope = -2.0 * smoothing_pressure / (max_altitude - smoothing_altitude)
    pressure_function.add_point(BezierPoint(max_altitude, 0.0, final_slope))

    return pressure_function


def main() -> None:
    # Vanilla overworld-like defaults used as an example for the generated curve.
    sea_level = 63.0
    min_y = -64.0
    logical_height = 704
    base_pressure = 1.0

    pressure_curve = create_default_pressure_curve(sea_level, min_y, logical_height)

    x_values = list(range(-100, 1001))
    y_values = [base_pressure * pressure_curve.evaluate_function(x) for x in x_values]

    plt.figure(figsize=(10, 5))
    plt.plot(x_values, y_values, label="Pressure")
    plt.axvline(
        sea_level, color="tab:green", linestyle="--", label=f"Sea level = {sea_level:g}"
    )
    plt.axvline(
        min_y + logical_height - 40.0,
        color="tab:orange",
        linestyle=":",
        label="Top smoothing start",
    )
    plt.axvline(
        min_y + logical_height, color="tab:red", linestyle="--", label="Build limit"
    )
    plt.xlim(-64, 704)
    plt.ylim(0, 1.6)
    plt.xlabel("Altitude (Y)")
    plt.ylabel("Pressure")
    plt.title("Sable Default Pressure Curve")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig("pressure_curve_overworld.png", dpi=160)

    print("Generated pressure_curve_overworld.png")
    print("Control points:")
    for point in pressure_curve.points:
        print(
            f"  altitude={point.altitude:.6f}, value={point.value:.6f}, slope={point.slope:.6f}"
        )


if __name__ == "__main__":
    main()
