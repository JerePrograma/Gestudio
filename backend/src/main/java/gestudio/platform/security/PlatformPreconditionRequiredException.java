package gestudio.platform.security;

public final class PlatformPreconditionRequiredException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    public PlatformPreconditionRequiredException(String message) {
        super(message);
    }
}
