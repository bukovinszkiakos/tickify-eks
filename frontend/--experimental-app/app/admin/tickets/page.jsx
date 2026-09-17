import { Suspense } from "react";
import AdminTicketsPage from "../../components/AdminTicketsPage";

export default function Page() {
  return (
    <Suspense fallback={<div>Loading tickets...</div>}>
      <AdminTicketsPage />
    </Suspense>
  );
}
