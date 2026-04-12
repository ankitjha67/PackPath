"""Fuel and toll cost estimation.

Heuristic-based for v1.1 — no live fuel-price API call. The numbers
come from per-region constants tuned to be roughly accurate today and
trivial to swap for a live source later.
"""

from __future__ import annotations

from dataclasses import dataclass


# Per-region defaults (per-litre / per-km in local currency cents)
_REGION_FUEL_PRICE_CENTS_PER_L = {
    "IN": 10500,  # ~₹105/L petrol
    "US": 35000,  # ~$3.50/gal converted
    "EU": 18000,  # ~€1.80/L
}
_REGION_TOLL_RATE_CENTS_PER_KM = {
    "IN": 300,  # ~₹3/km on FASTag highways
    "US": 0,    # mostly free
    "EU": 1000, # toll-heavy in FR/IT
}


@dataclass(frozen=True)
class VehicleProfile:
    name: str
    kmpl: float  # km per litre
    has_tolls: bool = True


_DEFAULT_VEHICLE = VehicleProfile(name="hatchback", kmpl=18.0)

_VEHICLES = {
    "hatchback": _DEFAULT_VEHICLE,
    "sedan": VehicleProfile(name="sedan", kmpl=15.0),
    "suv": VehicleProfile(name="suv", kmpl=12.0),
    "ev": VehicleProfile(name="ev", kmpl=0.0, has_tolls=True),  # cost via kWh
    "moto": VehicleProfile(name="moto", kmpl=40.0, has_tolls=False),
}


@dataclass(frozen=True)
class CostEstimate:
    fuel_cents: int
    toll_cents: int
    currency: str
    fuel_litres: float

    @property
    def total_cents(self) -> int:
        return self.fuel_cents + self.toll_cents


def estimate_cost(
    *,
    distance_m: float,
    region: str = "IN",
    vehicle: str = "hatchback",
) -> CostEstimate:
    profile = _VEHICLES.get(vehicle, _DEFAULT_VEHICLE)
    distance_km = distance_m / 1000.0
    if profile.kmpl > 0:
        litres = distance_km / profile.kmpl
        fuel_cents = int(
            litres * _REGION_FUEL_PRICE_CENTS_PER_L.get(region, 0)
        )
    else:
        # EV — use a flat per-km charging cost (~₹1.5/km on India fast chargers).
        litres = 0.0
        fuel_cents = int(distance_km * 150)
    toll_cents = (
        int(distance_km * _REGION_TOLL_RATE_CENTS_PER_KM.get(region, 0))
        if profile.has_tolls
        else 0
    )
    currency = {"IN": "INR", "US": "USD", "EU": "EUR"}.get(region, "INR")
    return CostEstimate(
        fuel_cents=fuel_cents,
        toll_cents=toll_cents,
        currency=currency,
        fuel_litres=round(litres, 2),
    )
