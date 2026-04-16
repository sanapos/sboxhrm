
// ==========================================
// src/layouts/MainLayout.tsx
// ==========================================
import { Outlet } from 'react-router-dom'
import { Sidebar } from '@/components/SideBar'
import { Header } from '@/components/Header'
import { SidebarProvider } from '@/contexts/SidebarContext'

export const MainLayout = () => {
  return (
    <SidebarProvider>
      <div className="flex h-screen bg-background overflow-hidden">
        <Sidebar />
        <div className="flex flex-col flex-1 overflow-hidden w-full">
          <Header />
          <main className="flex-1 overflow-y-auto p-4 md:p-6">
            <Outlet />
          </main>
        </div>
      </div>
    </SidebarProvider>
  )
}