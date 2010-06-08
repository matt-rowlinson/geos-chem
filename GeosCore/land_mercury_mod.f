!------------------------------------------------------------------------------
!          Harvard University Atmospheric Chemistry Modeling Group            !
!------------------------------------------------------------------------------
!BOP
!
! !MODULE: LAND_MERCURY_MOD
!
! !DESCRIPTION: Module LAND\_MERCURY\_MOD contains variables and routines for
! the land emissions for the GEOS-Chem mercury simulation. (eck, ccc, 6/2/10)
!\\
!\\
! !INTERFACE:
!
      MODULE LAND_MERCURY_MOD
!
! !USES:
!
      IMPLICIT NONE
      PRIVATE
!
! !PUBLIC MEMBER FUNCTIONS:
!
      PUBLIC :: BIOMASSHG
      PUBLIC :: VEGEMIS
      PUBLIC :: SOILEMIS
      PUBLIC :: LAND_MERCURY_FLUX
      PUBLIC :: GTMM_DR
      PUBLIC :: SNOWPACK_MERCURY_FLUX
      PUBLIC :: INIT_LAND_MERCURY
      PUBLIC :: CLEANUP_LAND_MERCURY
!
! !PRIVATE DATA MEMBERS:
!
      ! Plant transpiration rate [m/s]
      REAL*8,  ALLOCATABLE :: TRANSP(:,:)
!
! !REVISION HISTORY:
!
!  2 Jun 10 - C. Carouge  - Group all land emissions routine for mercury 
!                           into this new module.
!EOP
!------------------------------------------------------------------------------

      CONTAINS

!------------------------------------------------------------------------------
!          Harvard University Atmospheric Chemistry Modeling Group            !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: LAND_MERCURY_FLUX
!
! !DESCRIPTION: Subroutine LAND\_MERCURY\_FLUX calculates emissions of Hg(0) 
!  from prompt recycling of previously deposited mercury to land, in [kg/s].  
!  (eck, cdh, eds, 7/30/08)
!\\
!\\
! !INTERFACE:
!
      SUBROUTINE LAND_MERCURY_FLUX( LFLUX, LHGSNOW )
!
! !USES:
!
      USE TRACERID_MOD,  ONLY : ID_Hg0,          N_Hg_CATS
      USE LOGICAL_MOD,   ONLY : LSPLIT
      USE TIME_MOD,      ONLY : GET_TS_EMIS
      USE DAO_MOD,       ONLY : SNOW, SNOMAS 
!      USE OCEAN_MERCURY_MOD, ONLY : WD_HGP, WD_HG2, DD_HGP, DD_HG2
      USE DEPO_MERCURY_MOD, ONLY : WD_HGP, WD_HG2, DD_HGP, DD_HG2
      USE DAO_MOD,       ONLY : IS_ICE, IS_LAND

#     include "CMN_SIZE"      ! Size parameters

!
! !INPUT PARAMETERS:
!
      LOGICAL, INTENT(IN)   :: LHGSNOW
!
! !OUTPUT PARAMETERS:
!
      REAL*8,  INTENT(OUT)  :: LFLUX(IIPAR,JJPAR,N_Hg_CATS)
!
! !REVISION HISTORY:
!
!  (1 ) Now uses SNOWMAS from DAO_MOD for compatibility with GEOS-5.
!       (eds 7/30/08)
!  (2 ) Now includes REEMFRAC in parallelization; previous versions may have
!       overwritten variable. (cdh, eds 7/30/08)
!  (3 ) Now also reemit Hg(0) from ice surfaces, including sea ice 
!       (cdh, 8/19/08)
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!  
      REAL*8                :: DTSRCE, REEMFRAC, SNOW_HT
      REAL*8, PARAMETER     :: SEC_PER_YR = 365.25d0 * 86400d0
      INTEGER               :: I,      J,      NN

      !=================================================================
      ! LAND_MERCURY_FLUX begins here!
      !=================================================================

      ! Emission timestep [s]
      DTSRCE = GET_TS_EMIS() * 60d0     

!$OMP PARALLEL DO 
!$OMP+DEFAULT( SHARED ) 
!$OMP+PRIVATE( I, J, NN )
!$OMP+PRIVATE( REEMFRAC, SNOW_HT )  
      DO J  = 1, JJPAR
      DO I  = 1, IIPAR
      DO NN = 1, N_Hg_CATS
    
#if defined( GEOS_5 )
         ! GEOS5 snow height (water equivalent) in mm. (Docs wrongly say m)
         SNOW_HT = SNOMAS(I,J)
#else
         ! GEOS1-4 snow heigt (water equivalent) in mm
         SNOW_HT = SNOW(I,J)
#endif 
        
         ! If snow > 1mm on the ground, reemission fraction is 0.6,
         ! otherwise 0.2
         IF ( (SNOW_HT > 1D0) .OR. (IS_ICE(I,J)) ) THEN
            ! If snowpack model is on, then we don't do rapid reemission
            IF (LHGSNOW) THEN
               REEMFRAC=0d0
            ELSE
               REEMFRAC=0.6d0
            ENDIF 
         ELSE
            REEMFRAC=0.2d0
         ENDIF
         

         IF ( IS_LAND(I,J) .OR. IS_ICE(I,J) ) THEN 
            
            ! Mass of emitted Hg(0), kg
            LFLUX(I,J,NN) =
     &           ( WD_HgP(I,J,NN)+
     &           WD_Hg2(I,J,NN)+
     &           DD_HgP(I,J,NN)+
     &           DD_Hg2(I,J,NN) ) * REEMFRAC
            
            ! Emission rate of Hg(0). Convert kg /timestep -> kg/s
            LFLUX(I,J,NN) = LFLUX(I,J,NN) / DTSRCE
             
         ELSE
         
            ! No flux from non-land surfaces (water, sea ice)
            LFLUX(I,J,NN) = 0D0
         
         ENDIF

      ENDDO
      ENDDO
      ENDDO
!$OMP END PARALLEL DO
     
      ! Return to calling program
      END SUBROUTINE LAND_MERCURY_FLUX
!EOC
!------------------------------------------------------------------------------
!          Harvard University Atmospheric Chemistry Modeling Group            !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: BIOMASSHG
!
! !DESCRIPTION: Subroutine BIOMASSHG is the subroutine for Hg(0) emissions 
!  from biomass burning. These emissions are active only for present day 
!  simulations and not for preindustrial simulations (eck, cdh, eds, 7/30/08)
!
!  Emissions are based on an inventory of CO emissions from biomass burning 
!  (Duncan et al. J Geophys Res 2003), multiplied by a Hg/CO ratio in BB plumes
!  from Franz Slemr (Poster, EGU 2006).
!
!  Slemr surveyed emission factors from measurements worldwide. Although his
!  best estimate was 1.5e-7 mol Hg/ mol CO, we chose the highest value
!  (2.1e-7 mol Hg/ mol CO) in the range because the simulations shown in
!  Selin et al. (GBC 2008) required large Hg(0) emissions to sustain
!  reasonable atmospheric Hg(0) concentrations. (eck, 11/13/2008)
!\\
!\\
! !INTERFACE:
! 
      SUBROUTINE BIOMASSHG( EHg0_bb )
!
! !USES:
!     
      ! IDBCO moved from BIOMASS_MOD to TRACERID_MOD. (ccc, 5/6/10)
!      USE BIOMASS_MOD,    ONLY: BIOMASS, IDBCO
      USE BIOMASS_MOD,    ONLY: BIOMASS
      USE TRACERID_MOD,    ONLY: IDBCO
      USE LOGICAL_MOD,    ONLY: LBIOMASS, LPREINDHG
      USE TIME_MOD,       ONLY: GET_TS_EMIS
      USE GRID_MOD,       ONLY: GET_AREA_CM2

#     include "CMN_SIZE"     ! Size parameters
#     include "CMN_DIAG"     ! Diagnostic arrays & switches
!
! !OUTPUT PARAMETERS:
!
      REAL*8, DIMENSION(:,:),INTENT(OUT) :: EHg0_bb
!
! !REVISION HISTORY:
!
!EOP
!------------------------------------------------------------------------------
!BOC
! 
! !LOCAL VARIABLES:
!     
      REAL*8                 :: DTSRCE, E_CO, AREA_CM2
      INTEGER                :: I, J

      ! Hg molar mass, kg Hg/ mole Hg
      REAL*8,  PARAMETER   :: FMOL_HG     = 200.59d-3

      ! Hg/CO molar ratio in BB emissions, mol/mol
      ! emission factor 1.5e-7 molHg/molCO (Slemr et al poster EGU 2006)
      ! change emission factor to 2.1
      REAL*8,  PARAMETER   :: BBRatio_Hg_CO = 2.1D-7

      ! External functions
      REAL*8,  EXTERNAL      :: BOXVL

      !=================================================================
      ! BIOMASSHG begins here!
      !=================================================================

      ! DTSRCE is the number of seconds per emission timestep
      DTSRCE = GET_TS_EMIS() * 60d0

      ! Do biomass Hg emissions if biomass burning is on and it is a 
      ! present-day simulation (i.e. not preindustrial)
      IF ( LBIOMASS .AND. ( .NOT. LPREINDHG ) ) THEN

!$OMP PARALLEL DO
!$OMP+DEFAULT( SHARED )
!$OMP+PRIVATE( E_CO, I, J, AREA_CM2 )
         DO J = 1, JJPAR
         DO I = 1, IIPAR
 
            ! Grid box surface area, cm2
            AREA_CM2 = GET_AREA_CM2( J )

            ! Convert molec CO /cm3 /s -> mol CO /gridbox /s 
            E_CO = ( BIOMASS(I,J,IDBCO) / 6.022D23 ) * AREA_CM2

            ! Convert mol CO /gridbox /s to kg Hg /gridbox /s
            EHg0_bb(I,J) = E_CO * BBRatio_Hg_CO * FMOL_HG 
         
         ENDDO
         ENDDO
!$OMP END PARALLEL DO

      ELSE

         ! No emissions for preindustrial period, or when BB is turned off.
         EHg0_bb = 0D0

      ENDIF


      END SUBROUTINE BIOMASSHG
!EOC
!-----------------------------------------------------------------------------
!          Harvard University Atmospheric Chemistry Modeling Group            !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: VEGEMIS
!
! !DESCRIPTION: Subroutine VEGEMIS is the subroutine for Hg(0) emissions from 
!  vegetation by evapotranspiration. (eck, cdh, eds, 7/30/08)
!
!  Vegetation emissions are proportional to the evapotranspiration rate and the
!  soil water mercury content. We assume a constant concentration of mercury
!  in soil matter, based on the preindustrial and present-day simulations
!  described in Selin et al. (GBC 2008) and in SOILEMIS subroutine. From the
!  soil matter Hg concentration, we calculate a soil water Hg concentration in 
!  equilibrium (Allison and Allison, 2005).
!  NASA provides a climatology of evapotranspiration based on a water budget
!  model (Mintz and Walker, 1993).
!
! Calculate vegetation emissions following Xu et al (1999)
!    Fc = Ec Cw
!
!    Fc is Hg0 flux (ng m-2 s-1)
!    Ec is canopy transpiration (m s-1)
!    Cw is conc of Hg0 in surface soil water (ng m-3)
!
! Calculate Cw from the Allison and Allison (2005) equilibrium formula
!    Cw = Cs / Kd
!
!    Cs is the concentration of Hg is surface soil solids, ng/g
!    Kd is the equilibrium constant = [sorbed]/[dissolved]
!       log Kd = 3.8 L/kg -> Kd = 6310 L /kg = 6.31D-3 m3/g
!
! We assume a global mean Cs = 45 ng/g for the preindustrial period. In
! iterative simulations we redistribute this according to the deposition
! pattern while maintining the global mean. The scaling factor, EHg0_dist,
! also accounts for the anthropogenic enhancement of soil Hg in the present 
! day. 
!\\
!\\
! !INTERFACE:
!
      SUBROUTINE VEGEMIS( LGCAPEMIS, EHg0_dist, EHg0_vg )
!
! !USES:
!
      USE DAO_MOD,        ONLY: RADSWG, IS_LAND
      USE TIME_MOD,       ONLY: GET_MONTH, ITS_A_NEW_MONTH
      USE TIME_MOD,       ONLY: GET_TS_EMIS
      USE GRID_MOD,       ONLY: GET_AREA_M2

#     include "CMN_SIZE"     ! Size parameters
#     include "CMN_DEP"      ! FRCLND
!
! !INPUT PARAMETERS:
!
      LOGICAL,                INTENT(IN)  :: LGCAPEMIS
      REAL*8, DIMENSION(:,:), INTENT(IN)  :: EHg0_dist
!
! !OUTPUT PARAMETERS:
!
      REAL*8, DIMENSION(:,:), INTENT(OUT) :: EHg0_vg
!
! !REVISION HISTORY:
!
!EOP
!------------------------------------------------------------------------------
!BOC
! 
! !LOCAL VARIABLES:
!     
      REAL*8             :: DRYSOIL_HG, SOILWATER_HG, AREA_M2, VEG_EMIS
      INTEGER            :: I, J

      ! Soil Hg sorption to dissolution ratio, m3/g
      REAL*8, PARAMETER  :: Kd = 6.31D-3

      ! Preindustrial global mean soil Hg concentration, ng Hg /g dry soil
      REAL*8, PARAMETER  :: DRYSOIL_PREIND_HG = 45D0

      !=================================================================
      ! VEGEMIS begins here!
      !=================================================================

      ! No emissions through transpiration if we use Bess' GCAP emissions
      IF (LGCAPEMIS) THEN

         EHg0_vg = 0D0

      ELSE

         ! read GISS TRANSP monthly average
         IF ( ITS_A_NEW_MONTH() ) THEN 
            CALL READ_NASA_TRANSP
         ENDIF 

         ! loop over I,J
!$OMP PARALLEL DO
!$OMP+DEFAULT( SHARED )
!$OMP+PRIVATE( I, J, SOILWATER_HG, DRYSOIL_HG, VEG_EMIS, AREA_M2 ) 
         DO J=1, JJPAR
         DO I=1, IIPAR
        
            IF (IS_LAND(I,J)) THEN  

               ! Dry soil Hg concentration, ng Hg /g soil
               DRYSOIL_HG = DRYSOIL_PREIND_HG * EHg0_dist(I,J)

               ! Hg concentration in soil water, ng /m3
               SOILWATER_HG =  DRYSOIL_HG / Kd

               ! Emission from vegetation, ng /m2
               VEG_EMIS = SOILWATER_HG * TRANSP(I,J)

               ! convert from ng /m2 /s -> kg/gridbox/s
               ! Grid box surface area [m2]
               AREA_M2      = GET_AREA_M2( J )
               EHg0_vg(I,J) = VEG_EMIS * AREA_M2 * 1D-12

            ELSE

               ! No emissions from water and ice
               EHg0_vg(I,J) = 0D0

            ENDIF

         ENDDO
         ENDDO
!$OMP END PARALLEL DO

      ENDIF

      END SUBROUTINE VEGEMIS
!EOC
!------------------------------------------------------------------------------
!          Harvard University Atmospheric Chemistry Modeling Group            !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: SOILEMIS
!
! !DESCRIPTION: \subsection*{Overview}
!  Subroutine SIOLEMIS is the subroutine for Hg(0) emissions 
!  from soils. (eck, eds, 7/30/08)
!  
!  Soil emissions are a function of solar radiation at ground level 
!  (accounting for attenuation by leaf canopy) and surface temperature. 
!  The radiation dependence from Zhang et al. (2000) is multiplied by the 
!  temperature dependence from Poissant and Casimir (1998). 
!  Finally, this emission factor is multiplied by the soil mercury
!  concentration and scaled to meet the global emission total.
!
!\subsection*{Comments on soil Hg concentration}
!  We chose the preindustrial value of 45 ng Hg /g dry soil as the mean of
!  the range quoted in Selin et al. (GBC 2008): 20-70 ng/g (Andersson, 1967; 
!  Shacklette et al., 1971; Richardson et al., 2003; Frescholtz and Gustin,
!  2004). Present-day soil concentrations are thought to be 15% greater than
!  preindustrial (Mason and Sheu 2002), but such a difference is much less
!  than the range of concentrations found today, so not well constrained.
!  We calculate the present-day soil Hg distribution by adding a global mean
!  6.75 ng/g (=0.15 * 45 ng/g) according to present-day Hg deposition.
!  (eck, 11/13/08)
!\\
!\\
! !INTERFACE:
!
      SUBROUTINE SOILEMIS( EHg0_dist, EHg0_so )
!
! !USES:
!
      USE LAI_MOD,        ONLY: ISOLAI, MISOLAI, PMISOLAI, DAYS_BTW_M
      USE DAO_MOD,        ONLY: RADSWG, SUNCOS, TS, IS_LAND
      USE TIME_MOD,       ONLY: GET_MONTH, ITS_A_NEW_MONTH
      USE TIME_MOD,       ONLY: GET_TS_EMIS
      USE GRID_MOD,       ONLY: GET_AREA_M2
      USE DAO_MOD,        ONLY: SNOW, SNOMAS

#     include "CMN_SIZE"     ! Size parameters
#     include "CMN_DEP"      ! FRCLND
!
! !INPUT PARAMETERS:
!
      REAL*8, DIMENSION(:,:), INTENT(IN) :: EHg0_dist
!
! !OUTPUT PARAMETERS:
!
      REAL*8, DIMENSION(:,:), INTENT(OUT):: EHg0_so
!
! !REVISION HISTORY:
!
!  (1 ) Added comments. (cdh, eds, 7/30/08)
!  (2 ) Now include light attenuation by the canopy after sunset. Emissions
!       change by < 1% in high-emission areas  (cdh, 8/13/2008)
!  (3 ) Removed FRCLND for consistency with other Hg emissions (cdh, 8/19/08)
!  2 June 2010 - C. Carouge  - Solve  
!EOP
!------------------------------------------------------------------------------
!BOC
! 
! !LOCAL VARIABLES:
!     
      REAL*8             :: SOIL_EMIS, DIMLIGHT, TAUZ, LIGHTFRAC
      REAL*8             :: AREA_M2, DRYSOIL_HG, SNOW_HT
      INTEGER            :: I, J, JLOOP

      ! Preindustrial global mean soil Hg concentration, ng Hg /g dry soil
      REAL*8, PARAMETER  :: DRYSOIL_PREIND_HG = 45D0

      ! Scaling factor for emissions, g soil /m2 /h
      ! (This parameter is beta in Eq 3 of Selin et al., GBC 2008.
      ! The value in paper is actually DRYSOIL_PREIND_HG * SOIL_EMIS_FAC 
      ! and the stated units are incorrect. The paper should have stated
      ! beta = 1.5D15 / 45D0 = 3.3D13)
      ! This parameter is tuned in the preindustrial simulation 
      ! so that total deposition to soil equals total emission from soil,
      ! while also requiring global mean soil Hg concentration of 45 ng/g 
!      REAL*8, PARAMETER  :: SOIL_EMIS_FAC = 3.3D13
      REAL*8, PARAMETER  :: SOIL_EMIS_FAC = 2.4D-2 ! for sunlight function

      REAL*8              :: SUNCOSVALUE
      !=================================================================
      ! SOILEMIS begins here!
      !=================================================================

!$OMP PARALLEL DO
!$OMP+DEFAULT( SHARED )
!$OMP+PRIVATE( I, J, SOIL_EMIS, JLOOP,      SNOW_HT              ) 
!$OMP+PRIVATE( DRYSOIL_HG, TAUZ, LIGHTFRAC, AREA_M2, SUNCOSVALUE ) 
      DO J=1, JJPAR
      DO I=1, IIPAR
         
#if defined( GEOS_5 )
         ! GEOS5 snow height (water equivalent) in mm. (Docs wrongly say m)
         SNOW_HT = SNOMAS(I,J)
#else
         ! GEOS1-4 snow heigt (water equivalent) in mm
         SNOW_HT = SNOW(I,J)
#endif          
         
         IF ( IS_LAND(I,J) .AND. (SNOW_HT < 1d0) ) THEN     

            ! 1-D grid box index for SUNCOS
            JLOOP = ( (J-1) * IIPAR ) + I
         
            ! attenuate solar radiation based on function of leaf area index
            ! Jacob and Wofsy 1990 equations 8 & 9
            TAUZ = ISOLAI(I,J) * 0.5D0

            ! For very low and below-horizon solar zenith angles, use
            ! same attenuation as for SZA=85 degrees
            SUNCOSVALUE = MAX( SUNCOS(JLOOP), 0.09D0 )

            ! fraction of light reaching the surface is
            ! attenuated based on LAI
            LIGHTFRAC = EXP( -TAUZ / SUNCOSVALUE )

!------------------------------------------------------------------------------
! Prior to (cdh, ccc, 6/2/10)
!            ! if there is sunlight
!            IF (SUNCOS(JLOOP) > 0d0 .and. RADSWG(I,J) > 0d0 ) THEN
!
!               ! attenuate solar radiation based on function of leaf area index
!               ! Jacob and Wofsy 1990 equations 8 & 9
!               TAUZ = ISOLAI(I,J) * 0.5D0
!
!               ! fraction of light reaching the surface is
!               ! attenuated based on LAI
!               LIGHTFRAC = EXP( -TAUZ / SUNCOS(JLOOP) )
!
!            ELSE
!
!               ! If the sun has set, then set the canopy attenuation to
!               ! the same as for a high solar zenith angle, 80 deg
!               LIGHTFRAC = EXP( -TAUZ / 0.17D0 )
!
!            ENDIF
!------------------------------------------------------------------------------
            ! Dry soil Hg concentration, ng Hg /g soil
            DRYSOIL_HG = DRYSOIL_PREIND_HG * EHg0_dist(I,J)           

            ! Soil emissions, ng /m2 /h
            ! includes temperature and solar radiation effects
!            SOIL_EMIS = EXP( 1000D0 / TS(I,J) * -10.548D0 ) * 
!     &           EXP( 0.0011 * RADSWG(I,J) * LIGHTFRAC ) *
!     &           DRYSOIL_HG * SOIL_EMIS_FAC

! CDH try formula with just light dependence 10/18/2009
            SOIL_EMIS = 
     &           EXP( 0.0011 * RADSWG(I,J) * LIGHTFRAC ) *
     &           DRYSOIL_HG * SOIL_EMIS_FAC
     
            ! Grid box surface area [m2]
            AREA_M2   = GET_AREA_M2( J )
 
            ! convert soilnat from ng /m2 /h -> kg /gridbox /s
            EHg0_so(I,J) = SOIL_EMIS * AREA_M2 * 1D-12 / ( 60D0 * 60D0 )

         ELSE

            ! no soil emissions from water and ice
            EHg0_so(I,J) = 0D0
        
         ENDIF
        
      ENDDO
      ENDDO
!$OMP END PARALLEL DO

      WRITE(6,'(G12.3)') SUM(EHG0_SO)
    
      END SUBROUTINE SOILEMIS

!-----------------------------------------------------------------------------

      SUBROUTINE READ_NASA_TRANSP
!
!******************************************************************************
!  Subroutine READ_NASA_TRANSP reads monthly average transpirtation from NASA
!  http://gcmd.nasa.gov/records/GCMD_MINTZ_WALKER_SOIL_AND_EVAPO.html
!  for input into the vegetation emissions. (eck, 9/15/06)
!
!       Mintz, Y and G.K. Walker (1993). "Global fields of soil moisture
!       and land surface evapotranspiration derived from observed
!       precipitation and surface air temperature." J. Appl. Meteorol. 32 (8), 
!       1305-1334.
! 
!  Arguments as Input/Output:
!  ============================================================================
!  (1 ) TRANSP  : Transpiration [m/s]
!
!******************************************************************************
!

      ! References to F90 modules     
      USE TIME_MOD,       ONLY : GET_MONTH,  ITS_A_NEW_MONTH
      USE BPCH2_MOD,      ONLY : GET_TAU0,   READ_BPCH2
      USE TRANSFER_MOD,   ONLY : TRANSFER_2D

#     include "CMN_SIZE"      ! Size parameters

      ! Local variables
      INTEGER             :: I, J, L, MONTH, N
      REAL*4              :: ARRAY(IGLOB,JGLOB,1)
      REAL*8              :: XTAU
      CHARACTER(LEN=255)  :: FILENAME
      CHARACTER(LEN=2)    :: CMONTH(12) = (/ '01','02','03','04',
     &                                       '05','06','07','08',
     &                                       '09','10','11','12'/)
  
      !=================================================================
      ! READ_NASA_TRANSP begins here!
      !=================================================================

      ! Get the current month
      MONTH = GET_MONTH() 
     
!      FILENAME='/as/home/eck/transp/nasatransp_4x5.'
!     &        //CMONTH(MONTH)//'.bpch'
      FILENAME='/home/eck/emissions/transp/nasatransp_4x5.'
     &        //CMONTH(MONTH)//'.bpch'

      XTAU     = GET_TAU0(MONTH, 1, 1995 )

      ! Echo info
      WRITE( 6, 100 ) TRIM( FILENAME )
 100  FORMAT( '     - TRANSP_NASA: Reading ', a )     
 
      CALL READ_BPCH2( FILENAME, 'TRANSP-$', 1, 
     &                 XTAU,      IGLOB,     JGLOB,    
     &                 1,         ARRAY,   QUIET=.TRUE. )

      CALL TRANSFER_2D( ARRAY(:,:,1), TRANSP )
      
      ! convert from mm/month to m/s
      TRANSP = TRANSP * 1D-3 * 12D0 / ( 365D0 * 24D0 * 60D0 * 60D0 )
      
      END SUBROUTINE READ_NASA_TRANSP

!-----------------------------------------------------------------------------


      SUBROUTINE SNOWPACK_MERCURY_FLUX( FLUX, LHGSNOW )
!
!******************************************************************************
!  Subroutine SNOWPACK_MERCURY_FLUX calculates emission of Hg(0) from snow and
!  ice. Emissions are a linear function of Hg mass stored in the snowpack. The
!  Hg lifetime in snow is assumed to be 180 d when T< 270K and 7 d when T>270K
!
!     E = k * SNOW_HG     : k = 6D-8 if T<270K, 1.6D-6 otherwise
!
!  These time constants reflect the time scales of emission observed in the 
!  Arctic and in field studies. Holmes et al 2010
!
!  Arguments as Output
!  ============================================================================
!  (1 ) FLUX (REAL*8) : Flux of Hg(0) [kg/s]
!
!  NOTES:
!******************************************************************************
!
      ! References to F90 modules
      USE TRACERID_MOD,      ONLY : N_Hg_CATS
      USE TIME_MOD,          ONLY : GET_TS_EMIS
      USE DAO_MOD,           ONLY : T, SUNCOS
!      USE OCEAN_MERCURY_MOD, ONLY : SNOW_HG
      USE DEPO_MERCURY_MOD, ONLY : SNOW_HG

#     include "CMN_SIZE"      ! Size parameters

      ! Arguments 
      REAL*8,  INTENT(OUT)  :: FLUX(IIPAR,JJPAR,N_Hg_CATS)
      LOGICAL, INTENT(IN)   :: LHGSNOW

      ! Local variables
      INTEGER               :: I, J, NN, JLOOP
      LOGICAL, SAVE         :: FIRST
      REAL*8                :: DTSRCE, SNOW_HG_NEW, K_EMIT

      !=================================================================
      ! SNOWPACK_MERCURY_FLUX begins here!
      !=================================================================

      ! Initialize
      FLUX = 0D0

      ! Return to calling program if snowpack model is disabled
      IF (.NOT. LHGSNOW) RETURN

      ! Emission timestep [s]
      DTSRCE = GET_TS_EMIS() * 60d0      

      ! Emit Hg(0) at a steady rate, based on 180 d residence
      ! time in snowpack, based on cycle observed at Alert 
      ! (e.g. Steffen et al. 2008)
      K_EMIT = 6D-8

!$OMP PARALLEL DO 
!$OMP+DEFAULT( SHARED ) 
!$OMP+PRIVATE( I, J, NN )
!$OMP+PRIVATE( SNOW_HG_NEW, JLOOP, K_EMIT )
      DO J  = 1, JJPAR
      DO I  = 1, IIPAR

         ! 1-D grid box index for SUNCOS
         JLOOP = ( (J-1) * IIPAR ) + I

         ! If the sun is set, then no emissions, go to next box
         IF (SUNCOS(JLOOP)<0D0) CYCLE 

         ! Decrease residence time to 1 week when T > -3C
         IF (T(I,J,1) > 270D0) THEN
            K_EMIT = 1.6D-6
         ELSE
            K_EMIT = 6D-8
         ENDIF

         DO NN = 1, N_Hg_CATS

            ! Check if there is Hg that could be emitted
            IF (SNOW_HG(I,J,NN)>0D0) THEN

               ! New mass of snow in Hg
               SNOW_HG_NEW = SNOW_HG(I,J,NN) * EXP( - K_EMIT * DTSRCE )

               FLUX(I,J,NN) = MAX( SNOW_HG(I,J,NN) - SNOW_HG_NEW, 0D0 )

               ! Convert mass -> flux
               FLUX(I,J,NN) = FLUX(I,J,NN) / DTSRCE

               SNOW_HG(I,J,NN) = SNOW_HG_NEW

            ENDIF

         ENDDO

      ENDDO
      ENDDO
!$OMP END PARALLEL DO
      
      

      ! Return to calling program
      END SUBROUTINE SNOWPACK_MERCURY_FLUX

!------------------------------------------------------------------------------
!          Harvard University Atmospheric Chemistry Modeling Group            !
!------------------------------------------------------------------------------
!BOP
!
! !ROUTINE: GTMM\_DR
!
! !DESCRIPTION: GTMM\_DR is a driver to call GTMM from GEOS-Chem (ccc, 9/15/09)
!\\
!\\
! !INTERFACE: 
!
      SUBROUTINE GTMM_DR( Hg0gtm )
! 
! !USES:
!
      USE BPCH2_MOD
      USE DAO_MOD,           ONLY : IS_LAND
      USE FILE_MOD,          ONLY : IU_FILE, IOERROR
      USE TIME_MOD,          ONLY : EXPAND_DATE, YMD_EXTRACT
      USE TIME_MOD,          ONLY : GET_NYMD, GET_NHMS
      USE DIRECTORY_MOD,     ONLY : DATA_DIR_1x1
      USE DEPO_MERCURY_MOD,  ONLY : CHECK_DIMENSIONS
      USE DEPO_MERCURY_MOD,  ONLY : WD_Hg2, WD_HgP, DD_HgP, DD_Hg2
      USE DEPO_MERCURY_MOD,  ONLY : READ_GTMM_RESTART
    
#     include "CMN_SIZE"          ! Size parameters
!
! !INPUT PARAMETERS: 
!
      ! Emission of Hg0 calculated by GTMM for the month [kg/s]
      REAL*8, INTENT(OUT)   :: Hg0gtm(IIPAR, JJPAR) 
! 
! !REVISION HISTORY:
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      INTEGER   :: YEAR    ! Current year 
      INTEGER   :: MONTH   ! Current month
      INTEGER   :: DAY
      INTEGER   :: NYMD, NHMS
      

      REAL*8, DIMENSION(IIPAR, JJPAR)   :: TSURF    ! Ground temperature
      REAL*8, DIMENSION(IIPAR, JJPAR)   :: PRECIP   ! Total precipitation
                                                    ! for the month
      REAL*8, DIMENSION(IIPAR, JJPAR)   :: SOLAR_W  ! Solar radiation for 
                                                    ! the month

      REAL*4, DIMENSION(IIPAR, JJPAR)   :: TRACER   ! Temporary array

      ! Monthly average deposition arrays
      REAL*8, DIMENSION(IIPAR, JJPAR)   :: Hg0mth_dry
      REAL*8, DIMENSION(IIPAR, JJPAR)   :: Hg2mth_dry
      REAL*8, DIMENSION(IIPAR, JJPAR)   :: Hg2mth_wet

      INTEGER               :: IOS, I, J, L

      CHARACTER(LEN=255)    :: FILENAME

      ! For binary punch file, version 2.0
      INTEGER               :: NI,        NJ,      NL
      INTEGER               :: IFIRST,    JFIRST,  LFIRST
      INTEGER               :: HALFPOLAR, CENTER180
      INTEGER               :: NTRACER,   NSKIP
      REAL*4                :: LONRES,    LATRES
      REAL*8                :: ZTAU0,     ZTAU1
      CHARACTER(LEN=20)     :: MODELNAME
      CHARACTER(LEN=40)     :: CATEGORY
      CHARACTER(LEN=40)     :: UNIT     
      CHARACTER(LEN=40)     :: RESERVED


      !=================================================================
      ! GTMM_DR begins here!
      !=================================================================
      ! Initialise arrays
      NYMD      = GET_NYMD()
      NHMS      = GET_NHMS()

      TSURF   = 0d0
      PRECIP  = 0d0
      SOLAR_W = 0d0
      Hg0gtm  = 0d0

      ! Reset deposition arrays.
      Hg0mth_dry = 0d0
      Hg2mth_dry = 0d0
      Hg2mth_wet = 0d0

      CALL YMD_EXTRACT( NYMD, YEAR, MONTH, DAY )

      !=================================================================
      ! Read monthly meteorology fields
      !=================================================================

!--- Filename to use after tests (ccc)
!      FILENAME = TRIM( DATA_DIR ) // 'mercury_200501/' //
!     &           'GTM/MET_FIELDS/mean_YYYYMM.bpch'

      FILENAME = '/home/ccarouge/GTM/MET_FIELDS/' //
     &           'mean_200501.bpch'
    
      ! Replace YYYY, MM, DD, HH tokens in FILENAME w/ actual values
      CALL EXPAND_DATE( FILENAME, NYMD, NHMS )
    
      ! Echo some input to the screen
      WRITE( 6, '(a)' ) REPEAT( '=', 79 )
      WRITE( 6, 100   ) 
      WRITE( 6, 110   ) TRIM( FILENAME )
 100  FORMAT( 'G T M M  H g   M E T   F I L E   I N P U T' )
 110  FORMAT( /, 'GTMM_DR: Reading ', a )

      ! Open the binary punch file for input
      CALL OPEN_BPCH2_FOR_READ( IU_FILE, FILENAME )
    
      !-----------------------------------------------------------------
      ! Read concentrations -- store in the TRACER array
      !-----------------------------------------------------------------
      DO 
         READ( IU_FILE, IOSTAT=IOS )                              
     &        MODELNAME, LONRES, LATRES, HALFPOLAR, CENTER180
       
         ! IOS < 0 is end-of-file, so exit
         IF ( IOS < 0 ) EXIT
       
         ! IOS > 0 is a real I/O error -- print error message
         IF ( IOS > 0 ) CALL IOERROR( IOS, IU_FILE, 'rd_gtmm_dr:1' )
       
         READ( IU_FILE, IOSTAT=IOS )                               
     &        CATEGORY, NTRACER,  UNIT, ZTAU0,  ZTAU1,  RESERVED,  
     &        NI,       NJ,       NL,   IFIRST, JFIRST, LFIRST,    
     &        NSKIP
       
         IF ( IOS /= 0 ) CALL IOERROR( IOS, IU_FILE, 'rd_gtmm_dr:2' )
       
         READ( IU_FILE, IOSTAT=IOS )                               
     &        ( ( TRACER(I,J), I=1,NI ), J=1,NJ )
       
         IF ( IOS /= 0 ) CALL IOERROR( IOS, IU_FILE, 'rd_gtmm_dr:3' )
       
         !--------------------------------------------------------------
         ! Assign data from the TRACER array to the arrays.
         !--------------------------------------------------------------
       
         ! Process dry deposition data 
         IF ( CATEGORY(1:8) == 'GMAO-2D' ) THEN 
          
            ! Make sure array dimensions are of global size
            ! (NI=IIPAR; NJ=JJPAR, NL=1), or stop the run
            CALL CHECK_DIMENSIONS( NI, NJ, NL )
          
            ! Save into arrays
            IF ( NTRACER == 54 .OR. NTRACER == 59 ) THEN
             
               !----------
               ! Surface temperature
               !----------
             
               ! Store surface temperature in TSURF array
               TSURF(:,:)   = TRACER(:,JJPAR:1:-1)
             
            ELSE IF ( NTRACER == 26 .OR. NTRACER == 29 ) THEN
             
               !----------
               ! Total precipitation
               !----------
             
               ! Store precipitation in PRECIP array
               PRECIP(:,:)   = TRACER(:,JJPAR:1:-1)
             
            ELSE IF ( NTRACER == 37 .OR. NTRACER == 51 ) THEN

               !----------
               ! Solar radiation
               !----------

               ! Store solar radiation in SOLAR_W array
               SOLAR_W(:,:) = TRACER(:,JJPAR:1:-1)

            ENDIF
         ENDIF
       
      ENDDO
    
      ! Close file
      CLOSE( IU_FILE )      
    
      !=================================================================
      ! Read GTMM restart file to get data from previous month
      !=================================================================
      CALL READ_GTMM_RESTART(NYMD,      NHMS, Hg0mth_dry, Hg2mth_dry, 
     &                       Hg2mth_wet )

      !=================================================================
      ! Call GTMM model
      !=================================================================
#if defined( GTMM_Hg )
      CALL GTMM_coupled(YEAR                    , MONTH  , 
     &                  Hg0mth_dry(:,JJPAR:1:-1), 
     &                  Hg2mth_dry(:,JJPAR:1:-1), 
     &                  Hg2mth_wet(:,JJPAR:1:-1), TSURF  , PRECIP, 
     &                  SOLAR_W                  , Hg0gtm(:,JJPAR:1:-1)
     &                  )
#endif

      ! Use LAND/OCEAN mask on the land emissions
      DO J = 1, JJPAR
      DO I = 1, IIPAR
         IF ( .NOT.(IS_LAND(I, J)) ) Hg0gtm(I,J) = 0d0
      ENDDO
      ENDDO

      END SUBROUTINE GTMM_DR      
!EOC
!------------------------------------------------------------------------------

      SUBROUTINE INIT_LAND_MERCURY( )

!******************************************************************************
!  Subroutine INIT_LAND_MERCURY allocates and zeroes all module arrays.
!  (ccc, 9/14/09)
!  
!  NOTES:
!******************************************************************************
!
      ! References to F90 modules
      USE ERROR_MOD,    ONLY : ALLOC_ERR
      USE TRACERID_MOD, ONLY : N_Hg_CATS

#     include "CMN_SIZE"     ! Size parameters

      ! Local variables
      INTEGER                      :: AS
      LOGICAL, SAVE         :: IS_INIT = .FALSE. 

      !=================================================================
      ! INIT_MERCURY begins here!
      !=================================================================

      !=================================================================
      ! Allocate arrays
      !=================================================================
      ALLOCATE( TRANSP( IIPAR, JJPAR ), STAT=AS )
      IF ( AS /= 0 ) CALL ALLOC_ERR( 'TRANSP' )
      TRANSP = 0d0

      ! Return to calling program
      END SUBROUTINE INIT_LAND_MERCURY

!-----------------------------------------------------------------------------

      SUBROUTINE CLEANUP_LAND_MERCURY

!******************************************************************************
!  Subroutine CLEANUP_LAND_MERCURY deallocates all module arrays.
!  (ccc, 9/14/09)
!  
!  NOTES:
!******************************************************************************
!
      IF ( ALLOCATED( TRANSP      ) ) DEALLOCATE( TRANSP      )

      ! Return to calling program
      END SUBROUTINE CLEANUP_LAND_MERCURY

!-----------------------------------------------------------------------------

      END MODULE LAND_MERCURY_MOD
