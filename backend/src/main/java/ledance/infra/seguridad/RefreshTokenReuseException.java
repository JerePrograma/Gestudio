package ledance.infra.seguridad;

public class RefreshTokenReuseException extends RuntimeException {
    public RefreshTokenReuseException() {
        super("Refresh token reutilizado");
    }
}
