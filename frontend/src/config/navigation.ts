import {
  BarChart3,
  Building2,
  CalendarCheck,
  CreditCard,
  DollarSign,
  DoorOpen,
  Mic2,
  Package,
  Percent,
  PiggyBank,
  Receipt,
  Shield,
  Tags,
  TrendingUp,
  User,
  UserCheck,
  UserCog,
  Wallet,
  type LucideIcon,
} from "lucide-react";

export interface NavigationItem {
  id: string;
  icon?: LucideIcon;
  label: string;
  href?: string;
  description?: string;
  requiredPermission?: string;
  items?: NavigationItem[];
}

export const filterNavigationItems = (
  items: NavigationItem[],
  hasPermission: (permission: string) => boolean,
): NavigationItem[] => items
  .filter((item) => !item.requiredPermission || hasPermission(item.requiredPermission))
  .map((item) => ({
    ...item,
    items: item.items ? filterNavigationItems(item.items, hasPermission) : undefined,
  }))
  .filter((item) => item.href || (item.items?.length ?? 0) > 0);

export const navigationItems: NavigationItem[] = [
  { id: "alumnos", icon: User, label: "Alumnos", href: "/alumnos", requiredPermission: "ALUMNOS_READ" },
  { id: "cobranza", icon: DollarSign, label: "Cobranza", href: "/pagos/formulario", requiredPermission: "PAGOS_WRITE" },
  { id: "pagos", icon: Receipt, label: "Pagos", href: "/pagos", requiredPermission: "PAGOS_READ" },
  { id: "caja", icon: PiggyBank, label: "Caja", href: "/caja", requiredPermission: "CAJA_READ" },
  {
    id: "administracion",
    label: "Administración",
    icon: Building2,
    items: [
      { id: "egresos", label: "Egresos", href: "/egresos", icon: Wallet, requiredPermission: "EGRESOS_READ" },
      { id: "metodos-pago", label: "Métodos de pago", href: "/metodos-pago", icon: CreditCard, requiredPermission: "METODOS_PAGO_READ" },
      { id: "conceptos", label: "Conceptos", href: "/conceptos", icon: Tags, requiredPermission: "CONCEPTOS_READ" },
      { id: "stocks", label: "Stock", href: "/stocks", icon: Package, requiredPermission: "STOCK_READ" },
    ],
  },
  {
    id: "academico",
    label: "Gestión académica",
    icon: CalendarCheck,
    items: [
      { id: "inscripciones", label: "Inscripciones", href: "/inscripciones", icon: CalendarCheck, requiredPermission: "INSCRIPCIONES_READ" },
      { id: "asistencias", label: "Asistencias", href: "/asistencias/alumnos", icon: CalendarCheck, requiredPermission: "ASISTENCIAS_WRITE" },
      { id: "profesores", label: "Profesores", href: "/profesores", icon: UserCheck, requiredPermission: "PROFESORES_READ" },
      { id: "disciplinas", label: "Disciplinas", href: "/disciplinas", icon: Mic2, requiredPermission: "DISCIPLINAS_READ" },
      { id: "salones", label: "Salones", href: "/salones", icon: DoorOpen, requiredPermission: "DISCIPLINAS_READ" },
      { id: "bonificaciones", label: "Bonificaciones", href: "/bonificaciones", icon: Percent, requiredPermission: "BONIFICACIONES_READ" },
      { id: "recargos", label: "Recargos", href: "/recargos", icon: TrendingUp, requiredPermission: "RECARGOS_READ" },
    ],
  },
  { id: "reportes", label: "Alumnos por disciplina", href: "/alumnos-por-disciplina", icon: BarChart3, requiredPermission: "REPORTES_READ" },
  {
    id: "seguridad",
    label: "Seguridad",
    icon: Shield,
    items: [
      { id: "usuarios", label: "Usuarios", href: "/usuarios", icon: UserCog, requiredPermission: "USUARIOS_READ" },
      { id: "roles", label: "Roles", href: "/roles", icon: Shield, requiredPermission: "ROLES_READ" },
    ],
  },
];
