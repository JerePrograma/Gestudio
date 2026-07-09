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
import { PERMISSIONS } from "./permissions";

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
  {
    id: "alumnos",
    icon: User,
    label: "Alumnos",
    href: "/alumnos",
    requiredPermission: PERMISSIONS.APP_ACCESS,
  },
  {
    id: "cobranza",
    icon: DollarSign,
    label: "Cobranza",
    href: "/pagos/formulario",
    requiredPermission: PERMISSIONS.PAGOS_REGISTRAR,
  },
  {
    id: "pagos",
    icon: Receipt,
    label: "Pagos",
    href: "/pagos",
    requiredPermission: PERMISSIONS.APP_ACCESS,
  },
  {
    id: "caja",
    icon: PiggyBank,
    label: "Caja",
    href: "/caja",
    requiredPermission: PERMISSIONS.APP_ACCESS,
  },
  {
    id: "administracion",
    label: "Administración",
    icon: Building2,
    items: [
      {
        id: "egresos",
        label: "Egresos",
        href: "/egresos",
        icon: Wallet,
        requiredPermission: PERMISSIONS.EGRESOS_ADMIN,
      },
      {
        id: "metodos-pago",
        label: "Métodos de pago",
        href: "/metodos-pago",
        icon: CreditCard,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "conceptos",
        label: "Conceptos",
        href: "/conceptos",
        icon: Tags,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "stocks",
        label: "Stock",
        href: "/stocks",
        icon: Package,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
    ],
  },
  {
    id: "academico",
    label: "Gestión académica",
    icon: CalendarCheck,
    items: [
      {
        id: "inscripciones",
        label: "Inscripciones",
        href: "/inscripciones",
        icon: CalendarCheck,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "asistencias",
        label: "Asistencias",
        href: "/asistencias/alumnos",
        icon: CalendarCheck,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "profesores",
        label: "Profesores",
        href: "/profesores",
        icon: UserCheck,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "disciplinas",
        label: "Disciplinas",
        href: "/disciplinas",
        icon: Mic2,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "salones",
        label: "Salones",
        href: "/salones",
        icon: DoorOpen,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "bonificaciones",
        label: "Bonificaciones",
        href: "/bonificaciones",
        icon: Percent,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
      {
        id: "recargos",
        label: "Recargos",
        href: "/recargos",
        icon: TrendingUp,
        requiredPermission: PERMISSIONS.APP_ACCESS,
      },
    ],
  },
  {
    id: "reportes",
    label: "Alumnos por disciplina",
    href: "/alumnos-por-disciplina",
    icon: BarChart3,
    requiredPermission: PERMISSIONS.APP_ACCESS,
  },
  {
    id: "seguridad",
    label: "Seguridad",
    icon: Shield,
    items: [
      {
        id: "usuarios",
        label: "Usuarios",
        href: "/usuarios",
        icon: UserCog,
        requiredPermission: PERMISSIONS.USUARIOS_ADMIN,
      },
      {
        id: "roles",
        label: "Roles",
        href: "/roles",
        icon: Shield,
        requiredPermission: PERMISSIONS.ROLES_ADMIN,
      },
    ],
  },
];