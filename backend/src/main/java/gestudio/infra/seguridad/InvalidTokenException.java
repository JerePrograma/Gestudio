package gestudio.infra.seguridad;

public class InvalidTokenException extends RuntimeException {

    public InvalidTokenException(Throwable cause) {
        super("Token inválido", cause);
    }

    public InvalidTokenException() {
        super("Token inválido");
    }
}
