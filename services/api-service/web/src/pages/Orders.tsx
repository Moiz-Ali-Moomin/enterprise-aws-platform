import {
  AlertCircle,
  Box,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock,
  Filter,
  Plus,
  XCircle,
} from 'lucide-react'
import { useEffect, useState } from 'react'
import { cancelOrder, createOrder, getOrders, updateOrderStatus } from '../services/api'
import type { Order } from '../types'

const STATUSES = ['all', 'pending', 'processing', 'completed', 'cancelled'] as const
type StatusFilter = typeof STATUSES[number]

const STATUS_CONFIG = {
  pending:    { color: 'text-yellow-400', bg: 'bg-yellow-400/10', border: 'border-yellow-400/30', icon: Clock },
  processing: { color: 'text-blue-400',   bg: 'bg-blue-400/10',   border: 'border-blue-400/30',   icon: AlertCircle },
  completed:  { color: 'text-green-400',  bg: 'bg-green-400/10',  border: 'border-green-400/30',  icon: CheckCircle2 },
  cancelled:  { color: 'text-red-400',    bg: 'bg-red-400/10',    border: 'border-red-400/30',    icon: XCircle },
} as const

function StatusBadge({ status }: { status: string }) {
  const cfg = STATUS_CONFIG[status as keyof typeof STATUS_CONFIG] ?? STATUS_CONFIG.pending
  const Icon = cfg.icon
  return (
    <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium border ${cfg.color} ${cfg.bg} ${cfg.border}`}>
      <Icon size={11} />
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  )
}

export default function Orders() {
  const [orders, setOrders] = useState<Order[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [newProduct, setNewProduct] = useState('')
  const [newQty, setNewQty] = useState(1)
  const [newPrice, setNewPrice] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function load(p = page, sf = statusFilter) {
    setLoading(true)
    try {
      const res = await getOrders(p, 10, sf === 'all' ? undefined : sf)
      setOrders(res.items)
      setTotal(res.total)
      setTotalPages(res.total_pages)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load(1, statusFilter); setPage(1) }, [statusFilter])
  useEffect(() => { load(page, statusFilter) }, [page])

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    try {
      await createOrder({ product_name: newProduct, quantity: newQty, unit_price: parseFloat(newPrice) })
      setShowModal(false)
      setNewProduct(''); setNewQty(1); setNewPrice('')
      load(1, statusFilter); setPage(1)
    } finally {
      setSubmitting(false)
    }
  }

  async function handleStatusChange(order: Order, newStatus: string) {
    if (newStatus === 'cancel') { await cancelOrder(order.id) }
    else { await updateOrderStatus(order.id, newStatus) }
    load(page, statusFilter)
  }

  return (
    <div className="flex-1 bg-surface-900 overflow-auto">
      <div className="max-w-7xl mx-auto px-6 py-8">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold text-white">Orders</h1>
            <p className="text-gray-400 mt-1 text-sm">{total} total orders</p>
          </div>
          <button
            onClick={() => setShowModal(true)}
            className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-btn-gradient text-white text-sm font-medium shadow-glow hover:opacity-90 active:scale-[0.98] transition-all"
          >
            <Plus size={16} /> New Order
          </button>
        </div>

        {/* Filters */}
        <div className="flex items-center gap-2 mb-6">
          <Filter size={14} className="text-gray-500" />
          {STATUSES.map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all capitalize ${
                statusFilter === s
                  ? 'bg-brand-600/30 text-brand-300 border border-brand-500/40'
                  : 'text-gray-500 hover:text-gray-300 border border-white/5 hover:border-white/10'
              }`}
            >
              {s}
            </button>
          ))}
        </div>

        {/* Table */}
        <div className="bg-surface-800 border border-white/5 rounded-2xl">
          {loading ? (
            <div className="flex items-center justify-center py-20">
              <div className="w-8 h-8 border-4 border-brand-600 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : orders.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-20 text-gray-600">
              <Box size={40} className="mb-3 opacity-50" />
              <p className="font-medium">No orders found</p>
              <p className="text-sm mt-1">
                {statusFilter !== 'all' ? `No ${statusFilter} orders` : 'Create your first order'}
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-white/5">
                    {['Product', 'Qty', 'Unit Price', 'Total', 'Status', 'Date', 'Actions'].map((h) => (
                      <th key={h} className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {orders.map((order) => (
                    <tr key={order.id} className="hover:bg-white/[0.02] transition-colors">
                      <td className="px-6 py-4">
                        <p className="text-white text-sm font-medium">{order.product_name}</p>
                        <p className="text-gray-600 text-xs mt-0.5 font-mono">{order.id.slice(0, 8)}…</p>
                      </td>
                      <td className="px-6 py-4 text-gray-400 text-sm">{order.quantity}</td>
                      <td className="px-6 py-4 text-gray-400 text-sm">${order.unit_price.toFixed(2)}</td>
                      <td className="px-6 py-4 text-white text-sm font-semibold">${order.total_amount.toFixed(2)}</td>
                      <td className="px-6 py-4"><StatusBadge status={order.status} /></td>
                      <td className="px-6 py-4 text-gray-500 text-xs">
                        {new Date(order.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                      </td>
                      <td className="px-6 py-4">
                        {order.status === 'pending' && (
                          <div className="flex gap-2">
                            <button
                              onClick={() => handleStatusChange(order, 'processing')}
                              className="text-xs text-blue-400 hover:text-blue-300 transition-colors"
                            >
                              Process
                            </button>
                            <button
                              onClick={() => handleStatusChange(order, 'cancel')}
                              className="text-xs text-red-400 hover:text-red-300 transition-colors"
                            >
                              Cancel
                            </button>
                          </div>
                        )}
                        {order.status === 'processing' && (
                          <button
                            onClick={() => handleStatusChange(order, 'completed')}
                            className="text-xs text-green-400 hover:text-green-300 transition-colors"
                          >
                            Complete
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-between px-6 py-4 border-t border-white/5">
              <p className="text-gray-500 text-sm">
                Page {page} of {totalPages}
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1}
                  className="p-2 rounded-lg border border-white/10 text-gray-400 hover:text-white hover:border-white/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                >
                  <ChevronLeft size={16} />
                </button>
                <button
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={page === totalPages}
                  className="p-2 rounded-lg border border-white/10 text-gray-400 hover:text-white hover:border-white/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                >
                  <ChevronRight size={16} />
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Create Order Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-surface-800 border border-white/10 rounded-2xl p-6 w-full max-w-md shadow-card animate-slide-up">
            <h3 className="text-white font-semibold text-lg mb-5">New Order</h3>
            <form onSubmit={handleCreate} className="space-y-4">
              <div>
                <label className="block text-sm text-gray-300 mb-1.5">Product name</label>
                <input
                  value={newProduct}
                  onChange={(e) => setNewProduct(e.target.value)}
                  required
                  className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm text-gray-300 mb-1.5">Quantity</label>
                  <input
                    type="number" min={1} value={newQty}
                    onChange={(e) => setNewQty(Number(e.target.value))}
                    required
                    className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50"
                  />
                </div>
                <div>
                  <label className="block text-sm text-gray-300 mb-1.5">Unit price ($)</label>
                  <input
                    type="number" min={0} step={0.01} value={newPrice}
                    onChange={(e) => setNewPrice(e.target.value)}
                    required placeholder="0.00"
                    className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50"
                  />
                </div>
              </div>
              <div className="flex gap-3 pt-2">
                <button
                  type="button" onClick={() => setShowModal(false)}
                  className="flex-1 py-2.5 rounded-lg border border-white/10 text-gray-400 text-sm hover:bg-white/5 transition-all"
                >
                  Cancel
                </button>
                <button
                  type="submit" disabled={submitting}
                  className="flex-1 py-2.5 rounded-lg bg-btn-gradient text-white text-sm font-medium shadow-glow hover:opacity-90 disabled:opacity-50 transition-all"
                >
                  {submitting ? 'Creating...' : 'Create'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
