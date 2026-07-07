// Login.tsx
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../hooks/context/useAuth";
import Boton from "../componentes/comunes/Boton";
import { Form, Formik, Field, ErrorMessage } from "formik";
import * as yup from "yup";
import { prefetch } from "../rutas/routes";
import { Sparkles } from "lucide-react";

const loginSchema = yup.object().shape({
    nombreUsuario: yup.string().required("Nombre de Usuario es requerido"),
    contrasena: yup.string().required("Contraseña es requerida"),
});

const Login: React.FC = () => {
    const { login } = useAuth();
    const navigate = useNavigate();
    const [error, setError] = useState("");

    // Prefetch “en idle” del Dashboard (posible siguiente pantalla)
    useEffect(() => {
        const id = window.requestIdleCallback
            ? window.requestIdleCallback(() => prefetch.dashboard())
            : setTimeout(() => prefetch.dashboard(), 500);
        return () => {
            if (window.cancelIdleCallback) window.cancelIdleCallback(id);
            else clearTimeout(id);
        };
    }, []);

    const handleLogin = async (values: {
        nombreUsuario: string;
        contrasena: string;
    }) => {
        try {
            await login(values.nombreUsuario, values.contrasena);
            navigate("/");
        } catch {
            setError("Credenciales incorrectas. Intenta nuevamente.");
            // carga perezosa del bundle de notificaciones
            const { toast } = await import("react-toastify");
            toast.error("Error al iniciar sesión.");
        }
    };

    return (
        <main className="auth-page">
            <div className="auth-shell">
                <section className="auth-brand" aria-label="LE DANCE">
                    <div>
                        <span className="auth-brand-mark"><Sparkles className="size-6" aria-hidden="true" /></span>
                        <h1 className="auth-brand-title">Gestión clara para que la danza sea protagonista.</h1>
                        <p className="auth-brand-copy">Alumnos, clases, cobros y operación diaria en un solo panel administrativo.</p>
                    </div>
                    <p className="text-xs font-semibold uppercase tracking-[0.14em] text-background/55">LE DANCE · Panel de gestión</p>
                </section>
                <section className="auth-card">
                    <p className="page-eyebrow">Bienvenida</p>
                    <h2 className="mt-2 text-2xl font-bold sm:text-3xl">Iniciar sesión</h2>
                    <p className="mb-7 mt-2 text-sm leading-6 text-muted-foreground">Ingresá tus datos para acceder al panel administrativo.</p>
                    <Formik
                        initialValues={{ nombreUsuario: "", contrasena: "" }}
                        validationSchema={loginSchema}
                        validateOnBlur={false}
                        validateOnMount={false}
                        validateOnChange={false}
                        onSubmit={handleLogin}
                    >
                        {({ isSubmitting }) => (
                            <Form className="formulario">
                                <div className="field-group">
                                    <label htmlFor="nombreUsuario">Nombre de Usuario:</label>
                                    <Field
                                        id="nombreUsuario"
                                        name="nombreUsuario"
                                        className="form-input"
                                        placeholder="Tu nombre de usuario"
                                        autoComplete="username"
                                    />
                                    <ErrorMessage name="nombreUsuario" component="div" className="auth-error" />
                                </div>
                                <div className="field-group">
                                    <label htmlFor="contrasena">Contraseña:</label>
                                    <Field
                                        type="password"
                                        id="contrasena"
                                        name="contrasena"
                                        className="form-input"
                                        placeholder="Tu contraseña"
                                        autoComplete="current-password"
                                    />
                                    <ErrorMessage name="contrasena" component="div" className="auth-error" />
                                </div>
                                {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive" role="alert">{error}</div>}
                                <Boton type="submit" disabled={isSubmitting} className="page-button w-full">
                                    {isSubmitting ? "Ingresando…" : "Ingresar"}
                                </Boton>
                            </Form>
                        )}
                    </Formik>
                </section>
            </div>
        </main>
    );
};

export default Login;
