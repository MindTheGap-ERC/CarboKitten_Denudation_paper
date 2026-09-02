module FaciesParam
using CarboKitten
using CarboKitten.Models: WithDenudation as WDn
using CarboKitten.Production
using Unitful
export facies, input
const m = u"m"
const Myr = u"Myr"
const PERIOD = 0.2Myr
const AMPLITUDE = 20.0m

facies(reactive_surface,mass_density,infiltration_coefficient) = [
    WDn.Facies(
        production=Production.EXAMPLE[:euphotic],
        name="euphotic",
        transport_coefficient=50.0u"m/yr",
        reactive_surface=reactive_surface[1],
        mass_density=mass_density[1],
        infiltration_coefficient=infiltration_coefficient[1],
        erodibility = 0.0023u"m/yr"
        ),
    WDn.Facies(
        production=Production.EXAMPLE[:oligophotic],
        name="oligophotic",
        transport_coefficient=30.0u"m/yr",
        reactive_surface=reactive_surface[2],
        mass_density=mass_density[2],
        infiltration_coefficient=infiltration_coefficient[2],
        erodibility = 0.0023u"m/yr"
        ),
    WDn.Facies(
        production=Production.EXAMPLE[:aphotic],
        name="aphotic",
        transport_coefficient=10.0u"m/yr",
        reactive_surface=reactive_surface[3],
        mass_density=mass_density[3],
        infiltration_coefficient=infiltration_coefficient[3],
        erodibility = 0.0023u"m/yr"
        )
]

facies(erodibility) = [
    WDn.Facies(
        production=Production.EXAMPLE[:euphotic],
        name="euphotic",
        transport_coefficient=50.0u"m/yr",
        reactive_surface=10u"m^2/m^3",
        mass_density=2730u"kg/m^3",
        infiltration_coefficient=0.5,
        erodibility = erodibility[1]
        ),
    WDn.Facies(
        production=Production.EXAMPLE[:oligophotic],
        name="oligophotic",
        transport_coefficient=30.0u"m/yr",
        reactive_surface=10u"m^2/m^3",
        mass_density=2730u"kg/m^3",
        infiltration_coefficient=0.5,
        erodibility = erodibility[2]
        ),
    WDn.Facies(
        production=Production.EXAMPLE[:aphotic],
        name="aphotic",
        transport_coefficient=10.0u"m/yr",
        reactive_surface=10u"m^2/m^3",
        mass_density=2730u"kg/m^3",
        infiltration_coefficient=0.5,
        erodibility = erodibility[3]
        )
]

facies() = [
    WDn.Facies(
        production=Production.EXAMPLE[:euphotic],
        name="euphotic",
        transport_coefficient=50.0u"m/yr",
        reactive_surface=10u"m^2/m^3",
        mass_density=2730u"kg/m^3",
        infiltration_coefficient=0.5,
        erodibility = 0.0023u"m/yr"
        ),
    WDn.Facies(
        production=Production.EXAMPLE[:oligophotic],
        name="oligophotic",
        transport_coefficient=30.0u"m/yr",
        reactive_surface=10u"m^2/m^3",
        mass_density=2730u"kg/m^3",
        infiltration_coefficient=0.5,
        erodibility = 0.0023u"m/yr"
        ),
    WDn.Facies(
        production=Production.EXAMPLE[:aphotic],
        name="aphotic",
        transport_coefficient=10.0u"m/yr",
        reactive_surface=10u"m^2/m^3",
        mass_density=2730u"kg/m^3",
        infiltration_coefficient=0.5,
        erodibility = 0.0023u"m/yr"
        )
]


end