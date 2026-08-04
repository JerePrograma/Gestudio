package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.dto.request.LoginRequest;
import gestudio.entidades.RefreshSession;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tenancy.Tenant;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantMembership;
import gestudio.tenancy.TenantMembershipRole;
import gestudio.tenancy.TenantMembershipStatus;
import gestudio.tenancy.TenantSelection;
import gestudio.tenancy.TenantStatus;
import gestudio.tenancy.TenantMetrics;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.Optional;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class AutenticacionServiceTest {

    private static final String PASSWORD = "clave-admin-segura";

    private final UsuarioRepositorio usuarios = mock(UsuarioRepositorio.class);
    private final RefreshSessionService sessions = mock(RefreshSessionService.class);
    private final AuditFailureService auditFailures = mock(AuditFailureService.class);
    private final TenantAccessService tenantAccessService = mock(TenantAccessService.class);
    private final TokenService tokenService = mock(TokenService.class);
    private final TenantMetrics tenantMetrics = mock(TenantMetrics.class);
    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder(4);

    private final AutenticacionService autenticacion = new AutenticacionService(
            authenticationManager(),
            sessions,
            auditFailures,
            tenantAccessService,
            tokenService,
            tenantMetrics
    );

    @Test
    void loginExitosoConUsuarioYRolActivosYBcryptValido() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findCredencialesAutenticacion("admin"))
                .thenReturn(Optional.of(credenciales(usuario)));
        TenantAccess access = tenantAccess(usuario);
        when(tenantAccessService.activeSelections(usuario.getId())).thenReturn(List.of(access.tenant()));
        when(tenantAccessService.requireSelected(usuario.getId(), null)).thenReturn(access);

        RefreshSession session = new RefreshSession();
        session.setExpiresAt(Instant.parse("2026-07-07T00:00:00Z"));

        when(sessions.iniciar(usuario, access, "agent", "127.0.0.1"))
                .thenReturn(new RefreshSessionService.Emision(usuario, access, "access", "refresh", session));

        var resultado = autenticacion.login(new LoginRequest(" admin ", PASSWORD), "agent", "127.0.0.1");

        assertThat(resultado.accessToken()).isEqualTo("access");
        assertThat(resultado.refreshToken()).isEqualTo("refresh");
        assertThat(resultado.usuario().nombreUsuario()).isEqualTo("admin");
    }

    @Test
    void variasMembershipsExigenSeleccionYNoEmitenCredenciales() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));
        when(usuarios.findCredencialesAutenticacion("admin"))
                .thenReturn(Optional.of(credenciales(usuario)));
        when(tenantAccessService.activeSelections(usuario.getId())).thenReturn(List.of(
                new TenantSelection(UUID.randomUUID(), "academia-a", "Academia A", TenantStatus.ACTIVE),
                new TenantSelection(UUID.randomUUID(), "academia-b", "Academia B", TenantStatus.ACTIVE)
        ));

        var result = autenticacion.login(new LoginRequest("admin", PASSWORD), null, "127.0.0.1");

        assertThat(result.selectionRequired()).isTrue();
        assertThat(result.tenants()).extracting("codigo").containsExactly("academia-a", "academia-b");
        assertThat(result.accessToken()).isNull();
        assertThat(result.refreshToken()).isNull();
        verifyNoInteractions(sessions);
    }

    @Test
    void loginFallaConContrasenaIncorrecta() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findCredencialesAutenticacion("admin"))
                .thenReturn(Optional.of(credenciales(usuario)));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", "incorrecta"), null, "127.0.0.1"))
                .isInstanceOf(BadCredentialsException.class);

        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaConUsuarioInactivo() {
        Usuario usuario = usuario(false, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findCredencialesAutenticacion("admin"))
                .thenReturn(Optional.of(credenciales(usuario)));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(AuthenticationException.class);

        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaSinMembershipActiva() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findCredencialesAutenticacion("admin"))
                .thenReturn(Optional.of(credenciales(usuario)));
        when(tenantAccessService.activeSelections(usuario.getId())).thenReturn(List.of());
        when(tenantAccessService.requireSelected(usuario.getId(), null))
                .thenThrow(new org.springframework.security.access.AccessDeniedException("Tenant no autorizado"));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(BadCredentialsException.class);

        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaSiLaIdentidadCambiaDuranteLaSeleccionDelTenant() {
        Usuario credencial = usuario(true, true, passwordEncoder.encode(PASSWORD));
        Usuario actualizado = usuario(true, true, credencial.getContrasena());
        actualizado.setAuthVersion(credencial.getAuthVersion() + 1);
        TenantAccess access = tenantAccess(actualizado);

        when(usuarios.findCredencialesAutenticacion("admin"))
                .thenReturn(Optional.of(credenciales(credencial)));
        when(tenantAccessService.activeSelections(credencial.getId()))
                .thenReturn(List.of(access.tenant()));
        when(tenantAccessService.requireSelected(credencial.getId(), null)).thenReturn(access);

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(BadCredentialsException.class);

        verifyNoInteractions(sessions);
    }

    private ProviderManager authenticationManager() {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider(new UsuarioDetailsService(usuarios));
        provider.setPasswordEncoder(passwordEncoder);
        return new ProviderManager(provider);
    }

    private UsuarioRepositorio.CredencialesAutenticacion credenciales(Usuario usuario) {
        return new Credenciales(
                usuario.getId(),
                usuario.getNombreUsuario(),
                usuario.getContrasena(),
                usuario.getActivo(),
                usuario.getAuthVersion()
        );
    }

    private record Credenciales(Long id, String nombreUsuario, String contrasena, Boolean activo,
                                Long authVersion)
            implements UsuarioRepositorio.CredencialesAutenticacion {
        @Override public Long getId() { return id; }
        @Override public String getNombreUsuario() { return nombreUsuario; }
        @Override public String getContrasena() { return contrasena; }
        @Override public Boolean getActivo() { return activo; }
        @Override public Long getAuthVersion() { return authVersion; }
    }

    private Usuario usuario(boolean activo, boolean rolActivo, String hash) {
        Rol rol = new Rol(1L, "ADMINISTRADOR", rolActivo);
        rol.getPermisos().add(permiso("PERM_APP_ACCESO"));

        Usuario usuario = new Usuario();
        usuario.setId(1L);
        usuario.setNombreUsuario("admin");
        usuario.setContrasena(hash);
        usuario.setActivo(activo);
        usuario.setRol(rol);
        usuario.setRoles(new LinkedHashSet<>(java.util.List.of(rol)));
        usuario.setAuthVersion(0L);
        return usuario;
    }

    private gestudio.entidades.Permiso permiso(String codigo) {
        gestudio.entidades.Permiso permiso = new gestudio.entidades.Permiso();
        permiso.setCodigo(codigo);
        permiso.setDescripcion(codigo);
        permiso.setModulo("TEST");
        permiso.setActivo(true);
        permiso.setSistema(true);
        return permiso;
    }

    private TenantAccess tenantAccess(Usuario user) {
        Tenant tenant = new Tenant();
        tenant.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        tenant.setCode("TEST");
        tenant.setName("Test");
        tenant.setStatus(TenantStatus.ACTIVE);
        tenant.setSecurityVersion(0L);

        TenantMembership membership = new TenantMembership();
        membership.setId(UUID.fromString("20000000-0000-0000-0000-000000000001"));
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(TenantMembershipStatus.ACTIVE);
        membership.setSecurityVersion(0L);
        membership.setValidFrom(Instant.EPOCH);
        membership.getRoleAssignments().add(new TenantMembershipRole(membership, tenant, user.getRol()));
        return new TenantAccess(membership);
    }
}
