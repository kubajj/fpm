module fpm_manifest_profile
    use fpm_error, only : error_t, syntax_error
    use fpm_git, only : git_target_t, git_target_tag, git_target_branch, &
        & git_target_revision, git_target_default
    use fpm_toml, only : toml_table, toml_key, toml_stat, get_value
    implicit none
    private

    public :: profile_config_t, new_profile, new_profiles

    !> Configuration meta data for a profile
    type :: profile_config_t
      !> Name of the profile
      character(len=:), allocatable :: profile_name

      !> Name of the compiler
      character(len=:), allocatable :: compiler
      
      !> Name of the OS
      character(len=:), allocatable :: os
      
      !> Compiler flags
      character(len=:), allocatable :: compiler_flags

      contains

        !> Print information on this instance
        procedure :: info
    end type profile_config_t

    contains

      !> Construct a new profile configuration from a TOML data structure
      subroutine new_profile(self, profile_name, compiler, os, compiler_flags, error)
        type(profile_config_t), intent(out) :: self
        
        !> Name of the profile
        character(len=:), allocatable, intent(in) :: profile_name
        
        !> Name of the compiler
        character(len=:), allocatable, intent(in) :: compiler
        
        !> Name of the OS
        character(len=:), allocatable, intent(in) :: os
        
        !> Compiler flags
        character(len=:), allocatable, intent(in) :: compiler_flags
        
        !> Error handling
        type(error_t), allocatable, intent(out) :: error
       
        self%profile_name = profile_name
        self%compiler = compiler
        self%os = os
        self%compiler_flags = compiler_flags
      end subroutine new_profile

      !> Check if compiler name is a valid compiler name
      subroutine validate_compiler_name(compiler_name, is_valid)
        character(len=:), allocatable, intent(in) :: compiler_name
        logical, intent(out) :: is_valid
        select case(compiler_name)
          case("gfortran", "ifort", "ifx", "pgfortran", "nvfrotran", "flang", &
                        &"lfortran", "lfc", "nagfor", "crayftn", "xlf90", "ftn95")
            is_valid = .true.
          case default
            is_valid = .false.
        end select
      end subroutine validate_compiler_name

      !> Traverse operating system tables
      subroutine traverse_oss(profile_name, compiler_name, os_list, table, error, profiles_size, profiles, profindex)
        
        !> Name of profile
        character(len=:), allocatable, intent(in) :: profile_name

        !> Name of compiler
        character(len=:), allocatable, intent(in) :: compiler_name

        !> List of OSs in table with profile name and compiler name given
        type(toml_key), allocatable, intent(in) :: os_list(:)

        !> Table containing OS tables
        type(toml_table), pointer, intent(in) :: table

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        !> Number of profiles in list of profiles
        integer, intent(inout), optional :: profiles_size

        !> List of profiles
        type(profile_config_t), allocatable, intent(inout), optional :: profiles(:)

        !> Index in the list of profiles
        integer, intent(inout), optional :: profindex
        
        character(len=:), allocatable :: os_name
        type(toml_table), pointer :: os_node
        character(len=:), allocatable :: compiler_flags
        integer :: ios, stat

        if (size(os_list)<1) return
        do ios = 1, size(os_list)
          if (present(profiles_size)) then
            profiles_size = profiles_size + 1
          else
            if (.not.(present(profiles).and.present(profindex))) then
                    print *,"Error in traverse_oss"
                    return
            end if
            os_name = os_list(ios)%key       
            call get_value(table, os_name, os_node, stat=stat)
            if (stat /= toml_stat%success) then
              call syntax_error(error, "OS "//os_list(ios)%key//" must be a table entry")
              exit
            end if
            call get_value(os_node, 'flags', compiler_flags, stat=stat)
            if (stat /= toml_stat%success) then
              call syntax_error(error, "Compiler flags "//compiler_flags//" must be a table entry")
              exit
            end if
            call new_profile(profiles(profindex), profile_name, compiler_name, os_name, compiler_flags, error)
            profindex = profindex + 1
          end if
        end do
      end subroutine traverse_oss

      !> Traverse compiler tables
      subroutine traverse_compilers(profile_name, comp_list, table, error, profiles_size, profiles, profindex)
        
        !> Name of profile
        character(len=:), allocatable, intent(in) :: profile_name

        !> List of OSs in table with profile name given
        type(toml_key), allocatable, intent(in) :: comp_list(:)

        !> Table containing compiler tables
        type(toml_table), pointer, intent(in) :: table
        
        !> Error handling
        type(error_t), allocatable, intent(out) :: error
        
        !> Number of profiles in list of profiles
        integer, intent(inout), optional :: profiles_size

        !> List of profiles
        type(profile_config_t), allocatable, intent(inout), optional :: profiles(:)

        !> Index in the list of profiles
        integer, intent(inout), optional :: profindex
        
        character(len=:), allocatable :: compiler_name        
        type(toml_table), pointer :: comp_node
        type(toml_key), allocatable :: os_list(:)
        integer :: icomp, stat
        logical :: is_valid

        if (size(comp_list)<1) return
        do icomp = 1, size(comp_list)
          call validate_compiler_name(comp_list(icomp)%key, is_valid)
          if (is_valid) then  
            compiler_name = comp_list(icomp)%key
            call get_value(table, compiler_name, comp_node, stat=stat)
            if (stat /= toml_stat%success) then
              call syntax_error(error, "Compiler "//comp_list(icomp)%key//" must be a table entry")
              exit
            end if
            call comp_node%get_keys(os_list)
            if (present(profiles_size)) then
              call traverse_oss(profile_name, compiler_name, os_list, comp_node, error, profiles_size=profiles_size)
            else
              if (.not.(present(profiles).and.present(profindex))) then
                      print *,"Error in traverse_compilers"
                      return
              end if
              call traverse_oss(profile_name, compiler_name, os_list, comp_node, &
                                & error, profiles=profiles, profindex=profindex)
            end if
          end if
        end do        
      end subroutine traverse_compilers

      !> Construct new profiles array from a TOML data structure
      subroutine new_profiles(profiles, table, error)

        !> Instance of the dependency configuration
        type(profile_config_t), allocatable, intent(out) :: profiles(:)

        !> Instance of the TOML data structure
        type(toml_table), intent(inout) :: table

        !> Error handling
        type(error_t), allocatable, intent(out) :: error

        type(toml_table), pointer :: prof_node
        type(toml_key), allocatable :: prof_list(:)
        type(toml_key), allocatable :: comp_list(:)
        character(len=:), allocatable :: profile_name
        integer :: profiles_size, iprof, stat, profindex

        call table%get_keys(prof_list)
        
        if (size(prof_list) < 1) return
        
        profiles_size = 0

        do iprof = 1, size(prof_list)
          profile_name = prof_list(iprof)%key
          call get_value(table, profile_name, prof_node, stat=stat)
          if (stat /= toml_stat%success) then
            call syntax_error(error, "Profile "//prof_list(iprof)%key//" must be a table entry")
            exit
          end if
          call prof_node%get_keys(comp_list)
          call traverse_compilers(profile_name, comp_list, prof_node, error, profiles_size=profiles_size)
        end do
        
        allocate(profiles(profiles_size))
        
        profindex = 1

        do iprof = 1, size(prof_list)
          profile_name = prof_list(iprof)%key
          call get_value(table, profile_name, prof_node, stat=stat)
          call prof_node%get_keys(comp_list)
          call traverse_compilers(profile_name, comp_list, prof_node, error, profiles=profiles, profindex=profindex)
        end do
      end subroutine new_profiles
      
      !> Write information on instance
      subroutine info(self, unit, verbosity)

        !> Instance of the profile configuration
        class(profile_config_t), intent(in) :: self

        !> Unit for IO
        integer, intent(in) :: unit

        !> Verbosity of the printout
        integer, intent(in), optional :: verbosity

        integer :: pr
        character(len=*), parameter :: fmt = '("#", 1x, a, t30, a)'

        if (present(verbosity)) then
            pr = verbosity
        else
            pr = 1
        end if

        write(unit, fmt) "Profile"
        if (allocated(self%profile_name)) then
            write(unit, fmt) "- profile name", self%profile_name
        end if

        if (allocated(self%compiler)) then
            write(unit, fmt) "- compiler", self%compiler
        end if

        if (allocated(self%os)) then
            write(unit, fmt) "- os", self%os
        end if

        if (allocated(self%compiler_flags)) then
            write(unit, fmt) "- compiler flags", self%compiler_flags
        end if

      end subroutine info
end module fpm_manifest_profile
