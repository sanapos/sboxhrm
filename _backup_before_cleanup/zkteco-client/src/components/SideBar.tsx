
// ==========================================
// src/components/Sidebar.tsx
// ==========================================
import { NavLink } from 'react-router-dom'
import { 
  LayoutDashboard, 
  Monitor, 
  Users, 
  Clock, 
  Settings,
  X,
  Terminal,
  Calendar,
  CalendarCheck,
  CalendarClock,
  Receipt,
  UserCircle,
  Sheet
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { useSidebar } from '@/contexts/SidebarContext'
import { Button } from '@/components/ui/button'
import { useRoleAccess } from '@/hooks/useRoleAccess'
import { useMemo } from 'react'
import logoIcon from '@/assets/logo-icon.png'

const navItems = [
  { to: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/devices', icon: Monitor, label: 'Devices' },
  { to: '/device-commands', icon: Terminal, label: 'Commands' },
  { to: '/employees', icon: Users, label: 'Employees' },
  { to: '/device-users', icon: Users, label: 'Device Users' },
  { to: '/employee-info', icon: UserCircle, label: 'Employee Info' },
  { to: '/attendance', icon: Clock, label: 'Attendance' },
  { to: '/attendance-summary', icon: CalendarClock, label: 'Attendance Summary' },
  { to: '/my-shifts', icon: Calendar, label: 'My Shifts' },
  { to: '/shifts', icon: CalendarCheck, label: 'Shifts' },
  { to: '/leaves', icon: CalendarCheck, label: 'Leaves' },
  { to: '/payslips', icon: Receipt, label: 'Payslips' },
  { to: '/salary-profiles', icon: Settings, label: 'Benefits' },
  { to: '/google-sheets', icon: Sheet, label: 'Google Sheets' },
]

export const Sidebar = () => {
  const { isOpen, closeSidebar } = useSidebar()
  const { canAccessRoute } = useRoleAccess()

  // Filter navigation items based on user's role
  const allowedNavItems = useMemo(() => {
    return navItems.filter(item => canAccessRoute(item.to))
  }, [canAccessRoute])

  return (
    <>
      {/* Overlay for mobile */}
      {isOpen && (
        <div 
          className="fixed inset-0 bg-black/50 z-40 md:hidden"
          onClick={closeSidebar}
        />
      )}

      {/* Sidebar */}
      <aside 
        className={cn(
          'fixed md:static inset-y-0 left-0 z-50 bg-card border-r border-border',
          'transform transition-all duration-300 ease-in-out',
          isOpen ? 'translate-x-0 w-64' : '-translate-x-full md:translate-x-0 md:w-16',
        )}
      >
        <div className={cn(
          "flex items-center h-16 border-b border-border transition-all duration-300",
          isOpen ? "justify-between px-6" : "md:justify-center px-6 md:px-0"
        )}>
          <h1 className={cn(
            "text-xl font-bold text-primary transition-opacity duration-300 cursor-pointer",
            !isOpen && "md:hidden"
          )}>
            <img src={logoIcon} alt="Logo" className="w-15 h-10 inline-block" />
            <i>work</i><b style={{color: '#FFD700'}}>Fina</b>
          </h1>
          <Button
            variant="ghost"
            size="icon"
            className="md:hidden"
            onClick={closeSidebar}
          >
            <X className="w-5 h-5" />
          </Button>
        </div>
        <nav className={cn(
          "p-4 space-y-1 transition-all duration-300",
          !isOpen && "md:p-2"
        )}>
          {allowedNavItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              onClick={() => {
                // Close sidebar on mobile when navigating
                if (window.innerWidth < 768) {
                  closeSidebar()
                }
              }}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-3 px-4 py-3 rounded-lg transition-colors',
                  'hover:bg-accent hover:text-accent-foreground',
                  !isOpen && 'md:justify-center md:px-0 md:w-12 md:h-12',
                  isActive
                    ? 'bg-primary text-primary-foreground'
                    : 'text-muted-foreground'
                )
              }
              title={!isOpen ? item.label : undefined}
            >
              <item.icon className="w-5 h-5 flex-shrink-0" />
              <span className={cn(
                "font-medium transition-opacity duration-300",
                !isOpen && "md:hidden"
              )}>
                {item.label}
              </span>
            </NavLink>
          ))}
        </nav>
      </aside>
    </>
  )
}
